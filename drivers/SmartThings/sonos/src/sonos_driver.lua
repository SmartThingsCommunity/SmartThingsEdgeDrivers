local capabilities = require "st.capabilities"
local cosock = require "cosock"
local json = require "st.json"
local log = require "log"
local net_url = require "net.url"
local security = require "st.security"
local st_utils = require "st.utils"

local sonos_ssdp = require "api.sonos_ssdp_discovery"
local utils = require "utils"

local CmdHandlers = require "api.cmd_handlers"
local PlayerFields = require("fields").SonosPlayerFields
local SonosApi = require "api"
local SonosDisco = require "disco"
local SonosDriverLifecycleHandlers = require "lifecycle_handlers"
local SonosState = require "sonos_state"

---@class SonosDriver: Driver
---
---@field public datastore table<string, any> driver persistent store
---@field public dni_to_device_id table<string,string>
---@field public get_devices fun(self: SonosDriver): SonosDevice[]
---@field public get_device_info fun(self: SonosDriver, id: string): SonosDevice?
---
---@field public sonos SonosState Local state related to the sonos systems
---@field public discovery fun(driver: SonosDriver, opts: table, should_continue: fun(): boolean)
---
---@field public ssdp_task SonosPersistentSsdpTask?
---@field private ssdp_event_thread_handle table?
local SonosDriver = {}

---@param household_id HouseholdId
---@param player_id PlayerId
---@return SonosDevice?
function SonosDriver:device_for_player(household_id, player_id)
  local maybe_device_id = self.sonos:get_device_id_for_player(household_id, player_id)
  if maybe_device_id then
    return self:get_device_info(maybe_device_id)
  end
end

---@param dni string
---@return SonosDevice|nil
---@return string?
function SonosDriver:get_device_by_dni(dni)
  local cached_device_id = self.dni_to_device_id[dni]
  if cached_device_id then
    return self:get_device_info(cached_device_id)
  end

  for _, device in ipairs(self:get_devices() or {}) do
    if utils.mac_address_eq(device.device_network_id, dni) then
      self.dni_to_device_id[dni] = device.id
      return device
    end
  end

  return nil, string.format("Unable to find device record for DNI %s", dni)
end

function SonosDriver:get_api_key()
  return SonosApi.api_keys.s1_key
end

---Create a cosock task that handles events from the persistent SSDP task.
---@param driver SonosDriver
---@param discovery_event_subscription cosock.Bus.Subscription
local function make_ssdp_event_handler(driver, discovery_event_subscription)
  return function()
    local discovered = {}
    while true do
      local recv_ready, _, select_err =
        cosock.socket.select({ discovery_event_subscription }, nil, nil)

      if recv_ready then
        for _, receiver in ipairs(recv_ready) do

          if receiver == discovery_event_subscription then
            ---@type { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo, force_refresh: boolean }?
            local event, recv_err = discovery_event_subscription:receive()

            if event then
              local unique_key = utils.sonos_unique_key_from_ssdp(event.ssdp_info)
              if event.force_refresh or not discovered[unique_key] then
                local success, handle_err = driver:handle_player_discovery_info(SonosApi.api_keys.s1_key, event)
                if not success then
                  log.warn(string.format("Failed to handle discovered speaker: %s", handle_err))
                else
                  discovered[unique_key] = true
                end
              end
            else
              log.warn(string.format("Discovery event receive error: %s", recv_err))
            end
          end
        end
      else
        log.warn(string.format("SSDP Event Handler Select Error: %s", select_err))
      end
    end
  end,
    "SSDP Event Handler"
end

function SonosDriver:start_ssdp_event_task()
  local ssdp_task, err = sonos_ssdp.spawn_persistent_ssdp_task()
  if err then
    log.error(string.format("Unable to create SSDP task: %s", err))
  end
  if ssdp_task then
    self.ssdp_task = ssdp_task
    local ssdp_task_subscription = ssdp_task:subscribe()
    self.ssdp_event_thread_handle =
      cosock.spawn(make_ssdp_event_handler(self, ssdp_task_subscription))
  end
end

---@param api_key string
---@param info { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo, force_refresh: boolean }
---@param device SonosDevice?
---@return boolean|nil response nil or false on failure
---@return nil|string error the error reason on failure, nil on success
---@return nil|string error_code the Sonos error code, if available
function SonosDriver:handle_player_discovery_info(api_key, info, device)
  -- If the SSDP Group Info is an empty string, then that means it's the non-primary
  -- speaker in a bonded set (e.g. a home theater system, a stereo pair, etc).
  -- These aren't the same as speaker groups, and bonded speakers can't be controlled
  -- via websocket at all. So we ignore all bonded non-primary speakers
  if #info.ssdp_info.group_id == 0 then
    return nil,
      string.format("Player %s is a non-primary bonded Sonos device, ignoring", info.discovery_info.device.name)
  end

  api_key = api_key or self:get_api_key()

  local rest_url = net_url.parse(info.discovery_info.restUrl)
  local headers = SonosApi.make_headers(api_key)
  local response, response_err = SonosApi.RestApi.get_groups_info(rest_url, info.ssdp_info.household_id, headers)

  if response_err then
    return nil, string.format("Error while making REST API call: %s", response_err)
  end

  if response and response._objectType == "globalError" then
    local additional_info = response.reason or response.wwwAuthenticate
    local error_string = string.format(
      '`getGroups` response error for player "%s":\n\tError Code: %s',
      info.discovery_info.device.name,
      response.errorCode
    )

    if additional_info then
      error_string = string.format("%s\n\tadditional information: %s", error_string, additional_info)
    end


    return nil, error_string, response.errorCode
  end

  if response and response._objectType ~= "groups" then
    return nil,
      string.format(
        "Unexpected response type to group info request: %s",
        (response and response._objectType) or "<nil>"
      )
  end

  ---
  --- @cast response SonosGroupsResponseBody
  self.sonos:update_household_info(info.ssdp_info.household_id, response)

  local device_to_update, device_mac_addr

  local maybe_device_id = self.sonos:get_device_id_for_player(info.ssdp_info.household_id, info.discovery_info.playerId)

  if device then
    device_to_update = device
    device_mac_addr = device_to_update.device_network_id
  elseif maybe_device_id then
    local maybe_device_from_uuid = self:get_device_info(maybe_device_id)
    if maybe_device_from_uuid then
      device_to_update = maybe_device_from_uuid
      device_mac_addr = device_to_update.device_network_id
    end
  end

  if not device_mac_addr then
    device_mac_addr = utils.extract_mac_addr(info.discovery_info.device)
  end

  if not device_to_update then
    local maybe_device_from_dni = self:get_device_by_dni(device_mac_addr)
    if maybe_device_from_dni then
      device_to_update = maybe_device_from_dni
    end
  end

  if device_to_update then
    self.dni_to_device_id[device_mac_addr] = device_to_update.id
    self.sonos:associate_device_record(device_to_update, info)
  else
    local name = info.discovery_info.device.name
      or info.discovery_info.device.modelDisplayName
      or "Unknown Sonos Player"
    local model = info.discovery_info.device.modelDisplayName or "Unknown Sonos Model"
    local try_create_message = {
      type = "LAN",
      device_network_id = device_mac_addr,
      manufacturer = "Sonos",
      label = name,
      model = model,
      profile = "sonos-player",
      vendor_provided_label = info.discovery_info.device.model,
    }

    self:try_create_device(try_create_message)
  end
  return true
end

---@param driver SonosDriver
---@param device SonosDevice
---@param cmd any
local function do_refresh(driver, device, cmd)
  log.trace("Refreshing " .. device.label)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn == nil then
    log.error(string.format("Failed to do refresh, no sonos connection for device: [%s]", device.label))
    return
  end

  if not sonos_conn:is_running() then
    sonos_conn:start()
  end

  -- refreshing subscriptions should refresh all relevant data on those channels as well
  -- via the subscription confirmation events.
  sonos_conn:refresh_subscriptions()
end

function SonosDriver.new_driver_template()
  local template = {
    sonos = SonosState.instance(),
    discovery = SonosDisco.discover,
        lifecycle_handlers = SonosDriverLifecycleHandlers,
    dni_to_device_id = utils.new_mac_address_keyed_table(),
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = do_refresh,
      },
      [capabilities.audioMute.ID] = {
        [capabilities.audioMute.commands.mute.NAME] = CmdHandlers.handle_mute,
        [capabilities.audioMute.commands.unmute.NAME] = CmdHandlers.handle_unmute,
        [capabilities.audioMute.commands.setMute.NAME] = CmdHandlers.handle_set_mute,
      },
      [capabilities.audioNotification.ID] = {
        [capabilities.audioNotification.commands.playTrack.NAME] = CmdHandlers.handle_audio_notification,
        [capabilities.audioNotification.commands.playTrackAndResume.NAME] = CmdHandlers.handle_audio_notification,
        [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = CmdHandlers.handle_audio_notification,
      },
      [capabilities.audioVolume.ID] = {
        [capabilities.audioVolume.commands.volumeUp.NAME] = CmdHandlers.handle_volume_up,
        [capabilities.audioVolume.commands.volumeDown.NAME] = CmdHandlers.handle_volume_down,
        [capabilities.audioVolume.commands.setVolume.NAME] = CmdHandlers.handle_set_volume,
      },
      [capabilities.mediaGroup.ID] = {
        [capabilities.mediaGroup.commands.groupVolumeUp.NAME] = CmdHandlers.handle_group_volume_up,
        [capabilities.mediaGroup.commands.groupVolumeDown.NAME] = CmdHandlers.handle_group_volume_down,
        [capabilities.mediaGroup.commands.setGroupVolume.NAME] = CmdHandlers.handle_group_set_volume,
        [capabilities.mediaGroup.commands.muteGroup.NAME] = CmdHandlers.handle_group_mute,
        [capabilities.mediaGroup.commands.unmuteGroup.NAME] = CmdHandlers.handle_group_unmute,
        [capabilities.mediaGroup.commands.setGroupMute.NAME] = CmdHandlers.handle_group_set_mute,
      },
      [capabilities.mediaPlayback.ID] = {
        [capabilities.mediaPlayback.commands.play.NAME] = CmdHandlers.handle_play,
        [capabilities.mediaPlayback.commands.pause.NAME] = CmdHandlers.handle_pause,
        [capabilities.mediaPlayback.commands.stop.NAME] = CmdHandlers.handle_pause,
      },
      [capabilities.mediaPresets.ID] = {
        [capabilities.mediaPresets.commands.playPreset.NAME] = CmdHandlers.handle_play_preset,
      },
      [capabilities.mediaTrackControl.ID] = {
        [capabilities.mediaTrackControl.commands.nextTrack.NAME] = CmdHandlers.handle_next_track,
        [capabilities.mediaTrackControl.commands.previousTrack.NAME] = CmdHandlers.handle_previous_track,
      },
    },
  }

  for k, v in pairs(SonosDriver) do
    template[k] = v
  end

  return template
end

return SonosDriver
