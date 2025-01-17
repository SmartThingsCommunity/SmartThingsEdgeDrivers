local log = require "log"
local json = require "st.json"
local fields = require "fields"

local capabilities = require "st.capabilities"

local device_manager = {}
device_manager.__index = device_manager

local function is_new_audioTrackData(device, audioTrackData)
  local latestTrackData = device:get_latest_state("main", capabilities.audioTrackData.ID, capabilities.audioTrackData.audioTrackData.NAME, "")

  if not latestTrackData or latestTrackData == "" then
    return true
  end

  if (audioTrackData.title == latestTrackData.title)
      and (audioTrackData.artist == latestTrackData.artist)
      and (audioTrackData.album == latestTrackData.album)
      and (audioTrackData.albumArtUrl == latestTrackData.albumArtUrl)
      and (audioTrackData.mediaSource == latestTrackData.mediaSource) then
    return false
  end

  return true
end

local jbl_playback_state_to_smartthings_playback_status_table = {
  paused = "paused",
  playing = "playing",
}

function device_manager.handle_status(driver, device, status)
  if not status then
    log.error("device_manager.handle_status : status is nil")
    return
  end

  local playback_status = jbl_playback_state_to_smartthings_playback_status_table[status.playback]
  if playback_status and playback_status ~= device:get_latest_state("main", capabilities.mediaPlayback.ID, capabilities.mediaPlayback.playbackStatus.NAME, "") then
    log.info("device_manager.handle_status : update playbackStatus = " .. tostring(playback_status) .. ", dni = " .. tostring(device.device_network_id))
    device:emit_event(capabilities.mediaPlayback.playbackStatus[playback_status]())
  end

  if status.volume and status.volume ~= device:get_latest_state("main", capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME, 0) then
    log.info("device_manager.handle_status : update volume = " .. tostring(status.volume) .. ", dni = " .. tostring(device.device_network_id))
    device:emit_event(capabilities.audioVolume.volume(status.volume))
  end

  if status.mute and status.mute ~= "" and status.mute ~= device:get_latest_state("main", capabilities.audioMute.ID, capabilities.audioMute.mute.NAME, "") then
    log.info("device_manager.handle_status : update mute = " .. tostring(status.mute) .. ", dni = " .. tostring(device.device_network_id))
    device:emit_event(capabilities.audioMute.mute[status.mute]())
  end

  if status.track and status.track ~= '' then
    local audioTrackData = {}
    audioTrackData.title = status.track.title or ""
    audioTrackData.artist = status.track.artist or ""
    audioTrackData.album = status.track.album or ""
    if status.track.mediaSource then
      audioTrackData.mediaSource = status.track.mediaSource.name
    else
      audioTrackData.mediaSource = ""
    end

    if is_new_audioTrackData(device, audioTrackData) then
      log.info("device_manager.handle_status : update audioTrackData = " .. tostring(json.encode(audioTrackData)) .. ", dni = " .. tostring(device.device_network_id) .. tostring(json.encode(status)))
      device:emit_event(capabilities.audioTrackData.audioTrackData(audioTrackData))
      device:emit_event(capabilities.audioTrackData.totalTime(status.track.totalTime or 0))
    end
  end
end

function device_manager.update_status(driver, device)
  local conn_info = device:get_field(fields.CONN_INFO)

  if not conn_info then
    log.warn(" device_manager.update_status : failed to find conn_info, dni = " .. tostring(device.device_network_id))
    return
  end

  local response, err, status = conn_info:get_status()
  if err or status ~= 200 then
    log.error("device_manager.update_status : failed to get status, dni = " .. tostring(device.device_network_id) .. ", err = " .. tostring(err) .. ", status = " .. tostring(status))
    if status == 404 then
      log.info("device_manager.update_status : deleted, dni = " .. tostring(device.device_network_id))
      device:offline()
    end
    return
  end
  device_manager.handle_status(driver, device, response)
end

local sse_event_handlers = {
  ["message"] = device_manager.handle_status,
}

function device_manager.handle_sse_event(driver, device, event_type, data)
  local status, device_json = pcall(json.decode, data)
  if not status then
    log.error(string.format("handle_sse_event : failed to decode data"))
    return
  end

  local event_handler = sse_event_handlers[event_type]
  if event_handler then
    event_handler(driver, device, device_json)
  else
    log.error(string.format("handle_sse_event : unknown event type. dni = %s, event_type = '%s'", device.device_network_id, event_type))
  end
end

function device_manager.refresh(driver, device)
  device_manager.update_status(driver, device)
end

function device_manager.is_valid_connection(driver, device, conn_info)
  if not conn_info then
    log.error(" device_manager.is_valid_connection : failed to find conn_info, dni = " .. tostring(device.device_network_id))
    return false
  end
  local _, err, status = conn_info:get_status()
  if err or status ~= 200 then
    log.error(" device_manager.is_valid_connection : failed to connect to device, dni = " .. tostring(device.device_network_id) .. ", err = " .. tostring(err) .. ", status = " .. tostring(status))
    return false
  end

  return true
end

function device_manager.device_monitor(driver, device, device_info)
  log.info("device_monitor = " .. tostring(device.device_network_id))
  device_manager.refresh(driver, device)
end

function device_manager.get_sse_url(driver, device, conn_info)
  return conn_info:get_sse_url()
end

return device_manager
