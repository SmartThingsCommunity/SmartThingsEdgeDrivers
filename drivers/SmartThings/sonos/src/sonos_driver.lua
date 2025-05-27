local capabilities = require "st.capabilities"
local cosock = require "cosock"
local log = require "log"
local st_utils = require "st.utils"

local swGenCapability = capabilities["stus.softwareGeneration"]

local CmdHandlers = require "api.cmd_handlers"
local SonosApi = require "api"
local SonosDisco = require "disco"
local SonosRestApi = require "api.rest"
local SonosState = require "types".SonosState
local SSDP = require "ssdp"
local PlayerFields = require "fields".SonosPlayerFields
local SonosConnection = require "api.sonos_connection"
local utils = require "utils"

-- We use the same handler for added and init here because at the time of authoring
-- this driver, there is a bug with LAN Edge Drivers where `init` may not be called
-- on every device that gets created using `try_create_device`. This makes sure that
-- a device is fully initialized whether we come from fresh join or restart.
-- See: https://smartthings.atlassian.net/browse/CHAD-9683
local function _initialize_device(driver, device)
  if
    not (
      driver:get_device_by_dni(device.device_network_id)
      and driver:get_device_by_dni(device.device_network_id).id == device.id
    )
  then
    driver.dni_to_device_id[device.device_network_id] = device.id
  end
  if not device:get_field(PlayerFields._IS_SCANNING) then
    device.log.debug("Starting Scan in _initialize_device for %s", device.label)
    device:set_field(PlayerFields._IS_SCANNING, true)
    cosock.spawn(function()
      if not device:get_field(PlayerFields._IS_INIT) then
        log.trace(string.format("%s setting up device", device.label))
        local is_already_found = (
          (driver.found_ips and driver.found_ips[device.device_network_id])
          or driver.sonos:is_player_joined(device.device_network_id)
        ) and driver._field_cache[device.device_network_id]

        if not is_already_found then
          device.log.debug(
            string.format("Rescanning for player with DNI %s", device.device_network_id)
          )
          device:offline()
          local success = false

          local backoff = utils.backoff_builder(360, 1)
          while not success do
            success = driver:find_player_for_device(device)
            if not success then
              device.log.warn_with(
                { hub_logs = true },
                string.format(
                  "Couldn't find Sonos Player [%s] during SSDP scan, trying again shortly",
                  device.label
                )
              )
              cosock.socket.sleep(backoff())
            end
          end
        end

        device.log.trace("Setting persistent fields")
        local fields = driver._field_cache[device.device_network_id]
        driver:update_fields_from_ssdp_scan(device, fields)

        device:set_field(PlayerFields._IS_INIT, true)
      end

      local sonos_conn = device:get_field(PlayerFields.CONNECTION) --- @type SonosConnection

      if not sonos_conn then
        log.trace("Setting transient fields")
        -- device is offline until the websocket connection is established
        device:offline()
        sonos_conn = SonosConnection.new(driver, device)
        device:set_field(PlayerFields.CONNECTION, sonos_conn)
      end

      if not sonos_conn:is_running() then
        -- device is offline until the websocket connection is established
        device:offline()
        sonos_conn:start()
      else
        sonos_conn:refresh_subscriptions()
      end
    end, string.format("%s device init and SSDP scan", device.label))
  end
end

--- @param driver SonosDriver
--- @param device SonosDevice
local function device_added(driver, device)
  log.trace(string.format("%s device added", device.label))
  _initialize_device(driver, device)
end

local function emit_component_event_no_cache(device, component, capability_event)
  if not device:supports_capability(capability_event.capability, component.id) then
    local err_msg = string.format(
      "Attempted to generate event for %s.%s but it does not support capability %s",
      device.id,
      component.id,
      capability_event.capability.NAME
    )
    log.warn_with({ hub_logs = true }, err_msg)
    return false, err_msg
  end
  local event, err =
    capabilities.emit_event(device, component.id, device.capability_channel, capability_event)
  if err ~= nil then
    log.warn_with({ hub_logs = true }, err)
  end
  return event, err
end

--- @param driver SonosDriver
--- @param device SonosDevice
local function device_init(driver, device)
  log.trace(string.format("%s device init", device.label))
  _initialize_device(driver, device)

  -- Remove usage of the state cache for sonos devices to avoid large datastores
  device:set_field("__state_cache", nil, { persist = true })
  device:extend_device("emit_component_event", emit_component_event_no_cache)

  device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({
    capabilities.mediaPlayback.commands.play.NAME,
    capabilities.mediaPlayback.commands.pause.NAME,
    capabilities.mediaPlayback.commands.stop.NAME,
  }))

  device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands({
    capabilities.mediaTrackControl.commands.nextTrack.NAME,
    capabilities.mediaTrackControl.commands.previousTrack.NAME,
  }))
end

--- @param driver SonosDriver
--- @param device SonosDevice
local function device_removed(driver, device)
  log.trace(string.format("%s device removed", device.label))
  driver.dni_to_device_id[device.device_network_id] = nil
  local player_id = device:get_field(PlayerFields.PLAYER_ID)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn and sonos_conn:is_running() then
    sonos_conn:stop()
  end
  driver.sonos:mark_player_as_removed(device:get_field(PlayerFields.PLAYER_ID))
  driver._player_id_to_device[player_id] = nil
end

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

--- @param device SonosDevice
--- @param should_continue function|nil
function SonosDriver:find_player_for_device(device, should_continue)
  device.log.info(
    string.format("Looking for Sonos Player on network for device (%s)", device.device_network_id)
  )
  local player_found = false

  -- Because SSDP is UDP/unreliable, sometimes we can miss a broadcast.
  -- If the user doesn't provide a should_continue condition then we
  -- make one that just attempts it a handful of times.
  if type(should_continue) ~= "function" then
    should_continue = function()
      return false
    end
  end

  local dni_equal = self.is_same_mac_address
  repeat
    --- @param ssdp_group_info SonosSSDPInfo
    SSDP.search(SONOS_SSDP_SEARCH_TERM, function(ssdp_group_info)
      self:handle_ssdp_discovery(
        ssdp_group_info,
        function(dni, inner_ssdp_group_info, player_info, group_info)
          device.log.info(
            string.format(
              "Found device for Sonos search query with MAC addr %s, comparing to %s",
              dni,
              device.device_network_id
            )
          )
          if dni_equal(dni, device.device_network_id) then
            device.log.info(string.format("Found Sonos Player match for device"))

            self._field_cache[dni] = {
              household_id = inner_ssdp_group_info.household_id,
              player_id = player_info.playerId,
              wss_url = player_info.websocketUrl,
              swGen = player_info.device.swGen,
            }

            self.sonos:update_household_info(player_info.householdId, group_info)
            player_found = true
          end
        end
      )
    end)
  until player_found or (not should_continue())

  return player_found
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

function SonosDriver:scan_for_ssdp_updates()
  SSDP.search(SONOS_SSDP_SEARCH_TERM, function(ssdp_group_info)
    self:handle_ssdp_discovery(
      ssdp_group_info,
      function(dni, inner_ssdp_group_info, player_info, group_info)
        local current_cached_fields = self._field_cache[dni] or {}

        ---@type SonosFieldCacheTable
        local updated_fields = {
          household_id = inner_ssdp_group_info.household_id,
          player_id = player_info.playerId,
          wss_url = player_info.websocketUrl,
          swGen = player_info.device.swGen,
        }

        self._field_cache[dni] = updated_fields
        self.sonos:update_household_info(player_info.householdId, group_info)

        if not utils.deep_table_eq(current_cached_fields, updated_fields) then
          local device = self:get_device_by_dni(dni)
          if device then
            self:update_fields_from_ssdp_scan(device, updated_fields)
          end
        end
      end
    )
  end)
end

---@param header SonosResponseHeader
---@param body SonosGroupsResponseBody
function SonosDriver:update_group_state(header, body)
  self.sonos:update_household_info(header.householdId, body)
end

--- @param ssdp_group_info SonosSSDPInfo
--- @param callback? DiscoCallback
function SonosDriver:handle_ssdp_discovery(ssdp_group_info, callback)
  log.debug(
    string.format(
      "Looking for player info for SSDP search results %s",
      st_utils.stringify_table(ssdp_group_info)
    )
  )
  local player_info, err =
    SonosRestApi.get_player_info(ssdp_group_info.ip, SonosApi.DEFAULT_SONOS_PORT)

  if err then
    log.error("Error querying player info: " .. err)
  elseif player_info and player_info.playerId and player_info.householdId then
    log.debug(
      string.format(
        "Looking for group info for player info %s",
        st_utils.stringify_table(player_info)
      )
    )
    local group_info, err = SonosRestApi.get_groups_info(
      ssdp_group_info.ip,
      SonosApi.DEFAULT_SONOS_PORT,
      player_info.householdId
    )

    if err or not group_info then
      log.error("Error querying group info: " .. err)
      return
    end

    log.trace(
      string.format(
        "Device %s serial number: %s",
        player_info.device.name,
        player_info.device.serialNumber
      )
    )
    -- Extract the MAC Address from the serial number
    local mac_addr, _ = player_info.device.serialNumber:match("(.*):.*"):gsub("-", "")
    local dni = mac_addr
    log.trace(
      string.format("MAC of %s computed from serial number: %s", player_info.device.name, mac_addr)
    )

    if type(callback) == "function" then
      callback(dni, ssdp_group_info, player_info, group_info)
    end
  end
end

function SonosDriver.new_driver_template()
  local template = {
    discovery = SonosDisco.discover,
    lifecycle_handlers = {
      added = device_added,
      init = device_init,
      removed = device_removed,
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
