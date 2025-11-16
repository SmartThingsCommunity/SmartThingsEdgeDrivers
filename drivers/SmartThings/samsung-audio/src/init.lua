--  Copyright 2022 SmartThings
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
--  Improvements to be made:
--
--  ===============================================================================================
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local utils = require "st.utils"
local command = require "command"
local socket = require "cosock.socket"

-- local Listener = require "listener"
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
      local spk_name = device.name
      local spk_model = device.model
      log.info(string.format("Found a device. ip: %s, id: %s, device_name: %s, device_model: %s", device.ip, device.id, device.name, device.model))
      if not known_devices[id] and not found_devices[id] then
          local profile = "samsung-audio"
        -- add device
          local create_device_msg = {
            type = "LAN",
            device_network_id = id,
            label = spk_name,
            profile = profile,
            manufacturer = "Samsung",
            model = spk_model,
            vendor_provided_label = "SamsungAudio",
          }
          log.debug("Create device with:", utils.stringify_table(create_device_msg))
          assert(driver:try_create_device(create_device_msg))
          found_devices[id] = true
        --- end of add device
      else
        log.info("Discovered already known device")
      end
    end)
  end
  log.info("Ending discovery")
end


local function emit_refresh_data_to_server(driver, device, cmd)
  log.info("Refresh -> collecting updated data to send to server...")

  local info = command.getPlayStatus(device:get_field("ip"))
  if not info then
    log.error("Failed to get speaker state")
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    device:offline() -- Mark device as being unavailable/offline
    return
  end

  device:emit_event(capabilities.switch.switch.on()) --speaker is ON as its able to send back response
  if info.playstatus == "stop" then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  elseif info.playstatus == "pause" then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
  elseif info.playstatus == "play" then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
  elseif info.playstatus == "resume" then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
  else
    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  end

  device:online() -- Mark device as being online

  -- get volume
  local vol = command.volume(device:get_field("ip"))
  device:emit_event(capabilities.audioVolume.volume(tonumber(vol.volume)))

  -- get mute status
  local muteStatus = command.getMute(device:get_field("ip"))
  if muteStatus.muted ~= "off" then
    device:emit_event(capabilities.audioMute.mute.muted())
  else
    device:emit_event(capabilities.audioMute.mute.unmuted())
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
  log.info("HANDLING device_init lifecycle...")
  local backoff = backoff_builder(60, 1, 0.1)
  local dev_info
  while true do -- todo should we limit this? I think this will just spin forever if the device goes down
    local id_search = string.upper(device.device_network_id)
    log.debug(string.format("Trigger DISCOVERY to find a specific device having network ID --> %s", id_search))
    discovery.find(id_search, function(found) dev_info = found end)
    if dev_info then break end
    socket.sleep(backoff())
  end

  if not dev_info then
    log.warn("The specific device not found on network")
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

  emit_refresh_data_to_server(driver, device)

  -- start polling for device status (eventing)
  device.thread:call_on_schedule(120, function() emit_refresh_data_to_server(driver, device) end)

end


local function info_changed(driver, device, event, args)
  if device.label ~= args.old_st_store.label then
    local ip = device:get_field("ip")
    if not ip then
      log.warn("Failed to get device ip to update the speakers name")
    else
      command.setSpeakerName(ip, device.label)
    end
  end
end

local samsungAudio = Driver("samsung-audio", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handlers.handle_on,
      [capabilities.switch.commands.off.NAME] = handlers.handle_off,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = emit_refresh_data_to_server,
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
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME] = handlers.handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handlers.handle_volume_down,
      [capabilities.audioVolume.commands.setVolume.NAME] = handlers.handle_set_volume,
    },
  },
})

log.info("Start RUNNING Samsung-audio driver")
samsungAudio:run()
log.warn("Exiting Samsung-audio driver")
