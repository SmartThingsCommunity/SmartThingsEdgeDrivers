----------------------------------------------------------
-- Inclusions
----------------------------------------------------------
-- SmartThings inclusions
local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
local log = require "log"

-- local Harman Luxury inclusions
local discovery = require "disco"
local handlers = require "handlers"
local api = require "api.apis"
local const = require "constants"

----------------------------------------------------------
-- Device Functions
----------------------------------------------------------

local function stop_check_for_updates_thread(device)
  local current_timer = device:get_field(const.UPDATE_TIMER)
  if current_timer ~= nil then
    log.info(string.format("create_check_for_updates_thread: dni=%s, remove old timer", device.device_network_id))
    device.thread:cancel_timer(current_timer)
  end
end

local function device_removed(_, device)
  log.info("Device removed")
  -- cancel timers
  stop_check_for_updates_thread(device)
end

local function goOffline(device)
  stop_check_for_updates_thread(device)
  if device:get_field(const.STATUS) then
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    device:emit_event(capabilities.audioTrackData.audioTrackData({
      title = "",
    }))
  end
  device:set_field(const.STATUS, false, {
    persist = true,
  })
  device:offline()
end

local function refresh(_, device)
  local ip = device:get_field(const.IP)

  -- check and update device status
  local power_state
  power_state, _ = api.GetPowerState(ip)
  if power_state then
    log.debug(string.format("Current power state: %s", power_state))

    if power_state == "online" then
      device:emit_event(capabilities.switch.switch.on())
      local player_state, audioTrackData

      -- get player state
      player_state, _ = api.GetPlayerState(ip)
      if player_state then
        if player_state == "playing" then
          device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
        elseif player_state == "paused" then
          device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
        else
          device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
        end
      end

      -- get audio track data
      audioTrackData, _ = api.getAudioTrackData(ip)
      if audioTrackData then
        device:emit_event(capabilities.audioTrackData.audioTrackData(audioTrackData.trackdata))
        device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
                            audioTrackData.supportedPlaybackCommands))
        device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
                            audioTrackData.supportedTrackControlCommands))
        device:emit_event(capabilities.audioTrackData.totalTime(audioTrackData.totalTime or 0))
      end
    elseif device:get_field(const.STATUS) then
      device:emit_event(capabilities.switch.switch.off())
      device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    end
  end

  -- get media presets list
  local presets
  presets, _ = api.GetMediaPresets(ip)
  if presets then
    device:emit_event(capabilities.mediaPresets.presets(presets))
  end

  -- check and update device volume and mute status
  local vol, mute
  vol, _ = api.GetVol(ip)
  if vol then
    device:emit_event(capabilities.audioVolume.volume(vol))
  end
  mute, _ = api.GetMute(ip)
  if type(mute) == "boolean" then
    if mute then
      device:emit_event(capabilities.audioMute.mute.muted())
    else
      device:emit_event(capabilities.audioMute.mute.unmuted())
    end
  end

  -- check and update device media input source
  local inputSource
  inputSource, _ = api.GetInputSource(ip)
  if inputSource then
    device:emit_event(capabilities.mediaInputSource.inputSource(inputSource))
  end
end

local function check_for_updates(device)
  log.trace(string.format("%s, checking if device values changed", device.device_network_id))
  local ip = device:get_field(const.IP)
  local changes, err = api.InvokeGetUpdates(ip)
  -- check if changes is empty
  if not err then
    log.debug(string.format("changes: %s", st_utils.stringify_table(changes)))
    if type(changes) ~= "table" then
      log.warn("check_for_updates: Received value was not a table (JSON). Likely an error occured")
      return
    end
    -- check if there are any changes
    local next = next
    if next(changes) ~= nil then
      -- check for a power state change
      if changes["powerState"] then
        local powerState = changes["powerState"]
        if powerState == "online" then
          device:emit_event(capabilities.switch.switch.on())
        elseif powerState == "offline" then
          device:emit_event(capabilities.switch.switch.off())
        end
      end
      -- check for a player state change
      if changes["playerState"] then
        local playerState = changes["playerState"]
        if playerState == "playing" then
          device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
        elseif playerState == "paused" then
          log.debug("playerState - changed to paused")
          device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
        else
          device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
        end
      end
      -- check for a audio track data change
      if changes["audioTrackData"] then
        local audioTrackData = changes["audioTrackData"]
        local trackdata = {}
        if type(audioTrackData.title) == "string" then
          trackdata.title = audioTrackData.title
        else
          trackdata.title = ""
        end
        if type(audioTrackData.artist) == "string" then
          trackdata.artist = audioTrackData.artist
        end
        if type(audioTrackData.album) == "string" then
          trackdata.album = audioTrackData.album
        end
        if type(audioTrackData.albumArtUrl) == "string" then
          trackdata.albumArtUrl = audioTrackData.albumArtUrl
        end
        if type(audioTrackData.mediaSource) == "string" then
          trackdata.mediaSource = audioTrackData.mediaSource
        end
        -- if track changed
        device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))

        device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
                            audioTrackData.supportedPlaybackCommands) or {"play", "stop", "pause"})
        device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
                            audioTrackData.supportedTrackControlCommands) or {"nextTrack", "previousTrack"})
        device:emit_event(capabilities.audioTrackData.totalTime(audioTrackData.totalTime or 0))
      end
      -- check for a audio track data change
      if changes["elapsedTime"] then
        device:emit_event(capabilities.audioTrackData.elapsedTime(changes["elapsedTime"]))
      end
      -- check for a media presets change
      if changes["mediaPresets"] and type(changes["mediaPresets"].presets) == "table" then
        device:emit_event(capabilities.mediaPresets.presets(changes["mediaPresets"].presets))
      end
      -- check for a media input source change
      if changes["mediaInputSource"] then
        device:emit_event(capabilities.mediaInputSource.inputSource(changes["mediaInputSource"]))
      end
      -- check for a volume value change
      if changes["volume"] then
        device:emit_event(capabilities.audioVolume.volume(changes["volume"]))
      end
      -- check for a mute value change
      if changes["mute"] ~= nil then
        if changes["mute"] then
          device:emit_event(capabilities.audioMute.mute.muted())
        else
          device:emit_event(capabilities.audioMute.mute.unmuted())
        end
      end
    end
  end
end

local function create_check_for_updates_thread(device)
  -- stop old timer if one exists
  stop_check_for_updates_thread(device)

  log.info(string.format("create_check_for_updates_thread: dni=%s", device.device_network_id))
  local new_timer = device.thread:call_on_schedule(const.UPDATE_INTERVAL, function()
    check_for_updates(device)
  end, "value_updates_timer")
  device:set_field(const.UPDATE_TIMER, new_timer)
end

local function device_init(driver, device)
  log.info(string.format("Initiating device: %s", device.label))

  local device_ip = device:get_field(const.IP)
  local device_dni = device.device_network_id
  if driver.datastore.discovery_cache[device_dni] then
    log.warn("set unsaved device field")
    discovery.set_device_field(driver, device)
  end

  -- set supported default media playback commands
  device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
                      {capabilities.mediaPlayback.commands.play.NAME, capabilities.mediaPlayback.commands.pause.NAME,
                       capabilities.mediaPlayback.commands.stop.NAME}))
  device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
                      {capabilities.mediaTrackControl.commands.nextTrack.NAME,
                       capabilities.mediaTrackControl.commands.previousTrack.NAME}))

  -- set supported input sources
  local supportedInputSources, _ = api.GetSupportedInputSources(device_ip)
  device:emit_event(capabilities.mediaInputSource.supportedInputSources(supportedInputSources))

  -- set supported keypad inputs
  device:emit_event(capabilities.keypadInput.supportedKeyCodes(
                      {"UP", "DOWN", "LEFT", "RIGHT", "SELECT", "BACK", "EXIT", "MENU", "SETTINGS", "HOME", "NUMBER0",
                       "NUMBER1", "NUMBER2", "NUMBER3", "NUMBER4", "NUMBER5", "NUMBER6", "NUMBER7", "NUMBER8",
                       "NUMBER9"}))

  log.trace(string.format("device IP: %s", device_ip))

  create_check_for_updates_thread(device)

  refresh(driver, device)
end

local function update_connection(driver)
  log.debug("Entered update_connection()...")
  -- only test connections if there are registered devices
  local devices = driver:get_devices()
  if next(devices) ~= nil then
    local devices_ip_table = discovery.find_ip_table()
    for _, device in ipairs(devices) do
      local device_dni = device.device_network_id
      local device_ip = device:get_field(const.IP)
      local current_ip = devices_ip_table[device_dni]
      -- check if this device's dni appeared in the scan
      if current_ip then
        -- update IP associated to this device if changed
        if current_ip ~= device_ip then
          log.warn(string.format("Harman Luxury Driver updated %s IP to %s", device_dni, current_ip))
          device:set_field(const.IP, current_ip, {
            persist = true,
          })
        end
        -- set device online if credentials still match and update device IP if it changed
        local active_token, err = api.GetCredentialsToken(current_ip)
        if active_token then
          local device_token = device:get_field(const.CREDENTIAL)
          if active_token == device_token then
            -- if device is going back online after being offline we want to also reinitialize the device
            local state = device:get_field(const.STATUS)
            if state == false then
              device_init(driver, device)
            end
            device:set_field(const.STATUS, true, {
              persist = true,
            })
            device:online()
          else
            log.warn(string.format("device with dni: %s no longer holds the credential token", device_dni))
            goOffline(device)
          end
        else
          log.warn(string.format(
                     "device with dni: %s had issues while trying to read credentail token. Error message: %s",
                     device_dni, err))
          goOffline(device)
        end
      else
        -- set device offline if not detected
        log.warn(string.format(
                   "Harman Luxury Driver set %s offline as it didn't appear on latest update connections scan",
                   device_dni))
        goOffline(device)
      end
    end
  end
end

local function device_added(driver, device)
  log.info(string.format("Device added: %s", device.label))
  discovery.set_device_field(driver, device)
  local device_dni = device.device_network_id
  discovery.joined_device[device_dni] = nil
  -- ensuring device is initialised
  device_init(driver, device)
end

local function device_changeInfo(_, device, _, _)
  log.info(string.format("Device added: %s", device.label))
  local ip = device:get_field(const.IP)
  local _, err = api.SetDeviceName(ip, device.label)
  if err then
    log.info(string.format("device_changeInfo: Error occured during attempt to change device name. Error message: %s",
                           err))
  end
end

local function do_refresh(driver, device, _)
  log.info(string.format("Starting do_refresh: %s", device.label))

  -- check and update device values
  refresh(driver, device)
end

----------------------------------------------------------
-- Driver Definition
----------------------------------------------------------

--- @type Driver
local driver = Driver("Harman Luxury", {
  discovery = discovery.discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    infoChanged = device_changeInfo,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handlers.handle_on,
      [capabilities.switch.commands.off.NAME] = handlers.handle_off,
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.mute.NAME] = handlers.handle_mute,
      [capabilities.audioMute.commands.unmute.NAME] = handlers.handle_unmute,
      [capabilities.audioMute.commands.setMute.NAME] = handlers.handle_set_mute,
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME] = handlers.handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handlers.handle_volume_down,
      [capabilities.audioVolume.commands.setVolume.NAME] = handlers.handle_set_volume,
    },
    [capabilities.mediaInputSource.ID] = {
      [capabilities.mediaInputSource.commands.setInputSource.NAME] = handlers.handle_setInputSource,
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = handlers.handle_play_preset,
    },
    [capabilities.audioNotification.ID] = {
      [capabilities.audioNotification.commands.playTrack.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndResume.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = handlers.handle_audio_notification,
    },
    [capabilities.mediaPlayback.ID] = {
      [capabilities.mediaPlayback.commands.pause.NAME] = handlers.handle_pause,
      [capabilities.mediaPlayback.commands.play.NAME] = handlers.handle_play,
      [capabilities.mediaPlayback.commands.stop.NAME] = handlers.handle_stop,
    },
    [capabilities.mediaTrackControl.ID] = {
      [capabilities.mediaTrackControl.commands.nextTrack.NAME] = handlers.handle_next_track,
      [capabilities.mediaTrackControl.commands.previousTrack.NAME] = handlers.handle_previous_track,
    },
    [capabilities.keypadInput.ID] = {
      [capabilities.keypadInput.commands.sendKey.NAME] = handlers.handle_send_key,
    },
  },
  supported_capabilities = {capabilities.switch, capabilities.audioMute, capabilities.audioVolume,
                            capabilities.mediaPresets, capabilities.audioNotification, capabilities.mediaPlayback,
                            capabilities.mediaTrackControl, capabilities.refresh},
})

----------------------------------------------------------
-- Driver Routines
----------------------------------------------------------

-- create driver IP update routine

log.info("create health_check_timer for Harman Luxury devices")
driver:call_on_schedule(const.HEALTH_CHEACK_INTERVAL, function()
  update_connection(driver)
end, const.HEALTH_TIMER)

----------------------------------------------------------
-- main
----------------------------------------------------------

-- initialise data store for Harman Luxury driver

if driver.datastore.discovery_cache == nil then
  driver.datastore.discovery_cache = {}
end

-- start driver run loop

log.info("Starting Harman Luxury run loop")
driver:run()
log.info("Exiting Harman Luxury run loop")
