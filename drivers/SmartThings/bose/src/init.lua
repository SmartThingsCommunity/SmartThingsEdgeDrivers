--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--
--  ===============================================================================================
--  Up to date API references are available here:
--  https://developer.bose.com/guides/bose-soundtouch-api/bose-soundtouch-api-reference
--
--  Improvements to be made:
--
--  * Add mediaInputSource capability to support changing the speakers source
--  * Add support for controlling bose speaker zones by utilizing the mediaGroup capability
--  * Add support for detecting and updating the devices label when we receive the name changed update
--  * Use luncheon for commands and discovery
--  * Coalesce the parsing of xml payload from commands and websocket updates into a single place
--
--  ===============================================================================================
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local json = require "dkjson"
local utils = require "st.utils"
local command = require "command"
local socket = require "cosock.socket"

local Listener = require "listener"
local discovery = require "disco"
local handlers = require "handlers"

local function discovery_handler(driver, _, should_continue)
  log.info("Starting discovery")
  local known_devices = {}
  local found_devices = {}

  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    local id = device.device_network_id
    known_devices[id] = true
  end

  while should_continue() do
    discovery.find(nil, function(device) -- This is called after finding a device
      local id = device.id
      local ip = device.ip
      log.info(string.format("Found a device. ip: %s, id: %s", device.ip, device.id))
      if not known_devices[id] and not found_devices[id] then
        local dev_info, err = command.info(ip)
        if not dev_info then
          log.error(string.format("Failed to get info for device: %s", err))
        end
        local profile
        local app_key = pcall(require, "app_key") and require("app_key") or nil
        if app_key and #app_key > 0 then
          --Note all newly added devices will have the audio notification capability
          profile = "soundtouch-speaker-notification"
        else
          profile = "soundtouch-speaker"
        end
        local name = (dev_info.name or "Bose speaker")

        -- add device
        local create_device_msg = {
          type = "LAN",
          device_network_id = id,
          label = name,
          profile = profile,
          manufacturer = "Bose",
          model = dev_info.model or "unknown soundtouch",
          vendor_provided_label = "SoundTouch",
        }
        log.debug("Create device with:", utils.stringify_table(create_device_msg))
        assert(driver:try_create_device(create_device_msg))
        found_devices[id] = true
      else
        log.info("Discovered already known device")
      end
    end)
  end
  log.info("Ending discovery")
end

local toggle = true
local function do_refresh(driver, device, cmd)
  -- get speaker playback state
  local info, err = command.now_playing(device:get_field("ip"))
  if not info then
    log.error(string.format("failed to get speaker state: %s", err))
  elseif info.source == "STANDBY" then
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  else
    device:emit_event(capabilities.switch.switch.on())

    -- set play state
    if info.play_state == "STOP_STATE" then
      device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    elseif info.play_state == "PAUSE_STATE" then
      device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
    else
      device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
    end

    -- get audio track data
    local trackdata = {}
    trackdata.artist = info.artist
    trackdata.album = info.album
    trackdata.albumArtUrl = info.art_url
    trackdata.mediaSource = info.source
    if info.track then
      trackdata.title = info.track
    elseif info.station then
      trackdata.title = info.station
    elseif info.source == "AUX" then
      trackdata.title = "Auxilary input"
    end
    device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
    device:online()
  end

  -- get volume
  local vol, err = command.volume(device:get_field("ip"))
  if not vol then
    log.error(string.format("failed to get initial volume: %s", err))
  else
    device:emit_event(capabilities.audioVolume.volume(vol.actual))
    if vol.muted then device:emit_event(capabilities.audioMute.mute.muted()) end
  end

  -- get presets
  local presets, err = command.presets(device:get_field("ip"))
  if not presets then
    log.error(string.format("failed to get presets: %s", err))
  else
    device:emit_event(capabilities.mediaPresets.presets(presets))
  end
end

-- build a exponential backoff time value generator
--
-- max: the maximum wait interval (not including `rand factor`)
-- inc: the rate at which to exponentially back off
-- rand: a randomization range of (-rand, rand) to be added to each interval
local function backoff_builder(max, inc, rand)
  local count = 0
  inc = inc or 1
  return function()
    local randval = 0
    if rand then
      -- random value in range (-rand, rand)
      randval = math.random() * rand * 2 - rand
    end

    local base = inc * (2 ^ count - 1)
    count = count + 1

    -- ensure base backoff (not including random factor) is less than max
    if max then base = math.min(base, max) end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

local function device_init(driver, device)
  local backoff = backoff_builder(60, 1, 0.1)
  local dev_info
  while true do -- todo should we limit this? I think this will just spin forever if the device goes down
    discovery.find(device.device_network_id, function(found) dev_info = found end)
    if dev_info then break end
    socket.sleep(backoff())
  end

  if not dev_info then
    log.warn("device not found on network")
    return
  end

  device:set_field("ip", dev_info.ip, {persist = true})

  device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({
    capabilities.mediaPlayback.commands.play.NAME,
    capabilities.mediaPlayback.commands.pause.NAME,
    capabilities.mediaPlayback.commands.stop.NAME,
  }))
  device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands({
    capabilities.mediaTrackControl.commands.nextTrack.NAME,
    capabilities.mediaTrackControl.commands.previousTrack.NAME,
  }))
  do_refresh(driver, device)

  local listener = Listener.create_device_event_listener(driver, device)
  device:set_field("listener", listener)
  listener:start()
end

local function device_removed(driver, device)
  log.info("handling device removed...")
  local listener = device:get_field("listener")
  if listener then listener:stop() end
end

local function info_changed(driver, device, event, args)
  if device.label ~= args.old_st_store.label then
    local ip = device:get_field("ip")
    if not ip then
      log.warn("failed to get device ip to update the speakers name")
      local err = command.set_name(device.label)
      if err then log.error("failed to set device name") end
    end
  end
end

local bose = Driver("bose", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    removed = device_removed,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handlers.handle_on,
      [capabilities.switch.commands.off.NAME] = handlers.handle_off,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = handlers.handle_play_preset,
    },
    [capabilities.mediaPlayback.ID] = {
      [capabilities.mediaPlayback.commands.play.NAME] = handlers.handle_play,
      [capabilities.mediaPlayback.commands.pause.NAME] = handlers.handle_pause,
      [capabilities.mediaPlayback.commands.stop.NAME] = handlers.handle_stop,
    },
    [capabilities.mediaTrackControl.ID] = {
      [capabilities.mediaTrackControl.commands.nextTrack.NAME] = handlers.handle_next_track,
      [capabilities.mediaTrackControl.commands.previousTrack.NAME] = handlers.handle_previous_track,
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
    [capabilities.audioNotification.ID] = {
      [capabilities.audioNotification.commands.playTrack.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndResume.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = handlers.handle_audio_notification,
    },

  },
})

log.info("Starting bose driver")
bose:run()
log.warn("Exiting bose driver")
