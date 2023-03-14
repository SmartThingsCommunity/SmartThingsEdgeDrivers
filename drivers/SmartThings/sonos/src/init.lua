SONOS_API_KEY = require 'app_key'

local Driver = require "st.driver"

local capabilities = require "st.capabilities"
local log = require "log"

local CmdHandlers = require "api.cmd_handlers"
local PlayerFields = require "fields".SonosPlayerFields
local SonosApi = require "api"
local SonosConnection = require "api.sonos_connection"
local SonosDisco = require "disco"
local SonosRestApi = require "api.rest"
local SonosState = require "types".SonosState
local SSDP = require "ssdp"

--- @param driver SonosDriver
--- @param device SonosDevice
--- @param should_continue function|nil
local function find_player_for_device(driver, device, should_continue)
  local player_found = false

  -- Because SSDP is UDP/unreliable, sometimes we can miss a broadcast.
  -- If the user doesn't provide a should_continue condition then we
  -- make one that just attempts it a handful of times.
  if type(should_continue) ~= "function" then
    local attempts = 0
    should_continue = function()
      attempts = attempts + 1
      return attempts <= 10
    end
  end

  local dni_equal = driver.is_same_mac_address
  repeat
    --- @param ssdp_group_info SonosSSDPInfo
    SSDP.search(SONOS_SSDP_SEARCH_TERM, function(ssdp_group_info)
      driver:handle_ssdp_discovery(ssdp_group_info, function(dni, _, _, _)
        if dni_equal(dni, device.device_network_id) then
          player_found = true
        end
      end)
    end)
  until (player_found or (not should_continue()))

  return player_found
end

-- We use the same handler for added and init here because at the time of authoring
-- this driver, there is a bug with LAN Edge Drivers where `init` may not be called
-- on every device that gets created using `try_create_device`. This makes sure that
-- a device is fully initialized whether we come from fresh join or restart.
-- See: https://smartthings.atlassian.net/browse/CHAD-9683
local function _initialize_device(driver, device)
  if not device:get_field(PlayerFields._IS_INIT) then
    log.trace(string.format("%s setting up device", device.label))
    local is_already_found =
    ((driver.found_ips and driver.found_ips[device.device_network_id])
        or driver.sonos:is_player_joined(device.device_network_id)) and
        driver._field_cache[device.device_network_id]

    if not is_already_found then
      log.debug("Rescanning for player with DNI " .. device.device_network_id)
      local success = find_player_for_device(driver, device)
      if not success then
        device:offline()
        log.error(string.format(
          "Could not initialize Sonos Player [%s], it does not appear to be on the network",
          device.label
        ))
        return
      end
    end

    local fields = driver._field_cache[device.device_network_id]
    driver._player_id_to_device[fields.player_id] = device -- quickly look up device from player id string
    driver.sonos:mark_player_as_joined(fields.player_id)

    log.trace("Setting persistent fields")
    device:set_field(PlayerFields.WSS_URL, fields.wss_url, { persist = true })
    device:set_field(PlayerFields.HOUSEHOULD_ID, fields.household_id, { persist = true })
    device:set_field(PlayerFields.PLAYER_ID, fields.player_id, { persist = true })

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
end

--- @param driver SonosDriver
--- @param device SonosDevice
local function device_added(driver, device)
  log.trace(string.format("%s device added", device.label))
  _initialize_device(driver, device)
end

--- @param driver SonosDriver
--- @param device SonosDevice
local function device_init(driver, device)
  log.trace(string.format("%s device init", device.label))
  _initialize_device(driver, device)

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
  local player_id = device:get_field(PlayerFields.PLAYER_ID)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn and sonos_conn:is_running() then sonos_conn:stop() end
  driver.sonos:mark_player_as_removed(device:get_field(PlayerFields.PLAYER_ID))
  driver._player_id_to_device[player_id] = nil
end

local function do_refresh(driver, device, cmd)
  log.trace("Refreshing " .. device.label)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)

  if not sonos_conn:is_running() then
    sonos_conn:start()
  end

  -- refreshing subscriptions should refresh all relevant data on those channels as well
  -- via the subscription confirmation events.
  sonos_conn:refresh_subscriptions()
end

---@param self SonosDriver
---@param header SonosResponseHeader
---@param body SonosGroupsResponseBody
local function update_group_state(self, header, body)
  self.sonos:update_household_info(header.householdId, body)
end

--- @param self SonosDriver
--- @param ssdp_group_info SonosSSDPInfo
--- @param callback? fun(dni: string, ssdp_group_info: SonosSSDPInfo, player_info: SonosDiscoveryInfo, group_info: SonosGroupsResponseBody)
local function handle_ssdp_discovery(self, ssdp_group_info, callback)
  local player_info, err = SonosRestApi.get_player_info(ssdp_group_info.ip, SonosApi.DEFAULT_SONOS_PORT)

  if err then
    log.error("Error querying player info: " .. err)
  elseif player_info and player_info.playerId and player_info.householdId then
    local group_info, err = SonosRestApi.get_groups_info(
      ssdp_group_info.ip,
      SonosApi.DEFAULT_SONOS_PORT,
      player_info.householdId
    )

    if err or not group_info then
      log.error("Error querying group info: " .. err)
      return
    end

    -- Extract the MAC Address from the serial number
    local mac_addr, _ = player_info.device.serialNumber:match("(.*):.*"):gsub("-", "")
    local dni = mac_addr

    local field_cache = {
      household_id = ssdp_group_info.household_id,
      player_id = player_info.playerId,
      wss_url = player_info.websocketUrl
    }

    self._field_cache[dni] = field_cache

    self.sonos:update_household_info(player_info.householdId, group_info)

    if type(callback) == "function" then
      callback(dni, ssdp_group_info, player_info, group_info)
    end
  end
end

--- @type SonosDriver
local driver = Driver("Sonos", {
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
    }
  },
  sonos = SonosState.new(),
  update_group_state = update_group_state,
  handle_ssdp_discovery = handle_ssdp_discovery,
  _player_id_to_device = {},
  _field_cache = {},
  is_same_mac_address = function(dni, other)
    if not (type(dni) == "string" and type(other) == "string") then return false end
    local dni_normalized = dni:gsub("-", ""):gsub(":", ""):lower()
    local other_normalized = other:gsub("-", ""):gsub(":", ""):lower()
    return dni_normalized == other_normalized
  end
})

log.info("Starting Sonos run loop")
driver:run()
log.info("Exiting Sonos run loop")
