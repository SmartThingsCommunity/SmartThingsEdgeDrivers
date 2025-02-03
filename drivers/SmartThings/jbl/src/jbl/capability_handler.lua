local log = require "log"
local json = require "st.json"
local fields = require "fields"

local capability_handler = {}
capability_handler.__index = capability_handler

local function smartthings_playback_capability_handler(driver, device, capability_status)
  local st_status_to_jbl_playback_status_table = {
    paused = "pause",
    playing = "play",
  }

  local conn_info = device:get_field(fields.CONN_INFO)
  log.info(string.format("media-playback.set_playback_status_handler : dni = %s, status = %s", device.device_network_id, capability_status))

  local jbl_playback_status = st_status_to_jbl_playback_status_table[capability_status]

  local _, err, status = conn_info:post_playback(string.format('{"playback": "%s"}', jbl_playback_status))
  if not err and status == 200 then
    log.info(string.format("post_playback success, dni = %s", device.device_network_id))
  elseif status == 404 then
    log.error("404 error. delete device. dni = " .. tostring(device.device_network_id))
    device:offline()
  end
end

function capability_handler.playback_play_handler(driver, device, args)
  smartthings_playback_capability_handler(driver, device, "playing")
end

function capability_handler.playback_pause_handler(driver, device, args)
  smartthings_playback_capability_handler(driver, device, "paused")
end

function capability_handler.next_track_handler(driver, device, args)
  local conn_info = device:get_field(fields.CONN_INFO)
  log.info(string.format("media_track_control.next_track_handler : dni = %s", device.device_network_id))

  local _, err, status = conn_info:post_playback('{"playback": "next track"}')
  if err or status == 404 then
    log.error("media_track_control.next_track_handler : 404 error. delete device. dni = " .. tostring(device.device_network_id))
    device:offline()
  end
end

function capability_handler.previous_track_handler(driver, device, args)
  local conn_info = device:get_field(fields.CONN_INFO)
  log.info(string.format("media_track_control.previous_track_handler : dni = %s", device.device_network_id))

  local _, err, status = conn_info:post_playback('{"playback": "previous track"}')
  if err or status == 404 then
    log.error("media_track_control.previous_track_handler : 404 error. delete device. dni = " .. tostring(device.device_network_id))
    device:offline()
  end
end

function capability_handler.set_volume_handler(driver, device, args)
  local volume = args.args.volume
  local conn_info = device:get_field(fields.CONN_INFO)
  log.info(string.format("audio_volume.set_volume : dni = %s, volume = %d", device.device_network_id, volume))

  local _, err, status = conn_info:post_volume(string.format('{"volume": %d}', volume))
  if not err and status == 200 then
    log.info(string.format("post_volume success, dni = %s", device.device_network_id))
  elseif status == 404 then
    log.error("set_volume_handler : 404 error. delete device. dni = " .. tostring(device.device_network_id))
    device:offline()
  end
end

function capability_handler.audioNotification_handler(driver, device, args)
  local uri = args.args.uri
  local level = args.args.level
  local conn_info = device:get_field(fields.CONN_INFO)

  log.info(string.format("%s, %s : level = %s", args.capability, args.command, device.device_network_id, level))
  log.info(string.format("URI: %s", uri))

  local payload_table = {
    ["uri"] = uri,
  }

  if level then
    payload_table["volume"] = tostring(level)
    if args.command == "playTrackAndRestore" then
      payload_table["setToMasterVolume"] = false
    else
      payload_table["setToMasterVolume"] = true
    end
  end

  if args.command == "playTrackAndResume" then
    payload_table["resumeCurrentPlayback"] = true
  end

  local payload = json.encode(payload_table)

  conn_info:post_playback_uri(payload)
end

local function smartthings_audioMute_capability_handler(driver, device, mute_state)
  local conn_info = device:get_field(fields.CONN_INFO)
  local st_state_to_jbl_muted_state_table = {
    muted = "mute",
    unmuted = "unmute",
  }
  log.info(string.format("smartthings_audioMute_capability_handler dni = %s, status = %s", device.device_network_id, mute_state))

  local jbl_mute_state = st_state_to_jbl_muted_state_table[mute_state]

  local _, err, status = conn_info:post_playback(string.format('{"mute": "%s"}', jbl_mute_state))
  if not err and status == 200 then
    log.info(string.format("post_playback success, dni = %s", device.device_network_id))
  elseif status == 404 then
    log.error("smartthings_audioMute_capability_handler : 404 error. delete device. dni = " .. tostring(device.device_network_id))
    device:offline()
  end
end

function capability_handler.set_mute_handler(driver, device, args)
  local mute_state = args.args.state
  smartthings_audioMute_capability_handler(driver, device, mute_state)
end

function capability_handler.mute_handler(driver, device, args)
  smartthings_audioMute_capability_handler(driver, device, "muted")
end

function capability_handler.unmute_handler(driver, device, args)
  smartthings_audioMute_capability_handler(driver, device, "unmuted")
end

return capability_handler
