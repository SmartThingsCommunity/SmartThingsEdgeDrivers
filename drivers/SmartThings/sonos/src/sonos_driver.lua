local capabilities = require "st.capabilities"
local cosock = require "cosock"
local log = require "log"
local net_url = require "net.url"
local swGenCapability = capabilities["stus.softwareGeneration"]

local CmdHandlers = require "api.cmd_handlers"
local SonosApi = require "api"
local SonosDisco = require "disco"
local SonosDriverLifecycleHandlers = require "lifecycle_handlers"
local SonosState = require "types".SonosState
local PlayerFields = require "fields".SonosPlayerFields
local SonosConnection = require "api.sonos_connection"
local utils = require "utils"
local sonos_ssdp = require "api.sonos_ssdp_discovery"

local function do_refresh(driver, device, cmd)
  log.trace("Refreshing " .. device.label)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn == nil then
    log.error(
      string.format("Failed to do refresh, no sonos connection for device: [%s]", device.label)
    )
    return
  end

  if not sonos_conn:is_running() then
    sonos_conn:start()
  end

  -- refreshing subscriptions should refresh all relevant data on those channels as well
  -- via the subscription confirmation events.
  sonos_conn:refresh_subscriptions()
end

--- Sonos Edge Driver extensions
---@class SonosDriver : Driver
---@field public sonos SonosState Local state related to the sonos systems
---@field public datastore table<string, any> driver persistent store
---@field public dni_to_device_id table<string,string>
---@field public _player_id_to_device table<string,SonosDevice>
---@field public _field_cache table<string,SonosFieldCacheTable>
local SonosDriver = {}

function SonosDriver.is_same_mac_address(dni, other)
  if not (type(dni) == "string" and type(other) == "string") then
    return false
  end
  local dni_normalized = dni:gsub("-", ""):gsub(":", ""):lower()
  local other_normalized = other:gsub("-", ""):gsub(":", ""):lower()
  return dni_normalized == other_normalized
end

function SonosDriver:get_device_by_dni(dni)
  local device_uuid = self.dni_to_device_id[dni]
  if not device_uuid then
    return nil
  end
  return self:get_device_info(device_uuid)
end

---@param header SonosResponseHeader
---@param body SonosGroupsResponseBody
function SonosDriver:update_group_state(header, body)
  self.sonos:update_household_info(header.householdId, body)
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

---@param device SonosDevice
---@param fields SonosFieldCacheTable
function SonosDriver:update_fields_from_ssdp_scan(device, fields)
  device.log.debug("Updating fields from SSDP scan")
  local is_initialized = device:get_field(PlayerFields._IS_INIT)

  local current_player_id, current_url, current_household_id, sonos_conn, sw_gen

  if is_initialized then
    current_player_id = device:get_field(PlayerFields.PLAYER_ID)
    current_url = device:get_field(PlayerFields.WSS_URL)
    current_household_id = device:get_field(PlayerFields.HOUSEHOLD_ID)
    sonos_conn = device:get_field(PlayerFields.CONNECTION)
    sw_gen = device:get_field(PlayerFields.SW_GEN)
  end

  local already_connected = sonos_conn ~= nil
  local refresh = false

  if current_player_id ~= fields.player_id then
    if current_player_id ~= nil then
      self._player_id_to_device[current_player_id] = nil
      self.sonos:mark_player_as_removed(current_player_id)
      refresh = true
    end
    self._player_id_to_device[fields.player_id] = device -- quickly look up device from player id string
    self.sonos:mark_player_as_joined(fields.player_id)
    device:set_field(PlayerFields.PLAYER_ID, fields.player_id, { persist = true })
  end

  if current_household_id ~= fields.household_id then
    if current_household_id ~= nil then
      refresh = true
    end
    device:set_field(PlayerFields.HOUSEHOLD_ID, fields.household_id, { persist = true })
  end

  if current_url ~= fields.wss_url then
    if current_url ~= nil and sonos_conn ~= nil then
      sonos_conn:stop()
      sonos_conn = nil
      device:set_field(PlayerFields.CONNECTION, nil)
      refresh = true
    end
    device:set_field(PlayerFields.WSS_URL, fields.wss_url, { persist = true })
  end

  if sw_gen ~= fields.swGen then
    device:set_field(PlayerFields.SW_GEN, fields.swGen, { persist = true })
    device:emit_event(swGenCapability.generation(string.format("%s", fields.swGen)))
  end

  if refresh and already_connected then
    if not sonos_conn then
      sonos_conn = SonosConnection.new(self, device)
      device:set_field(PlayerFields.CONNECTION, sonos_conn)
      -- calls refresh subscriptions for us
      sonos_conn:start()
      return
    end

    sonos_conn:refresh_subscriptions()
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

  api_key = api_key or SonosApi.api_keys.s1_key

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


  --- @cast response SonosGroupsResponseBody
  self.sonos:update_household_info(info.ssdp_info.household_id, response)

  local device_to_update, device_mac_addr

  device = device or self._player_id_to_device[info.discovery_info.playerId]

  if device then
    device_to_update = device
    device_mac_addr = device_to_update.device_network_id
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


  local current_cached_fields = self._field_cache[device_mac_addr or ""] or {}

  ---@type SonosFieldCacheTable
  local updated_fields = {
    household_id = info.ssdp_info.household_id,
    player_id = info.discovery_info.playerId,
    wss_url = info.discovery_info.websocketUrl,
    swGen = info.discovery_info.device.swGen,
  }

  self._field_cache[device_mac_addr] = updated_fields

  if device_to_update and not utils.deep_table_eq(current_cached_fields, updated_fields)then
    self.dni_to_device_id[device_mac_addr] = device_to_update.id
    self:update_fields_from_ssdp_scan(device_to_update, updated_fields)
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

function SonosDriver.new_driver_template()
  local template = {
    discovery = SonosDisco.discover,
    lifecycle_handlers = {
      added = SonosDriverLifecycleHandlers.added,
      init = SonosDriverLifecycleHandlers.init,
      removed = SonosDriverLifecycleHandlers.removed,
    },
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
    sonos = SonosState.new(),
    _player_id_to_device = {},
    _field_cache = {},
    dni_to_device_id = {},
  }

  for k, v in pairs(SonosDriver) do
    template[k] = v
  end

  return template
end

return SonosDriver
