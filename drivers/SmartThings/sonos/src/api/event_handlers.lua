local capabilities = require "st.capabilities"
local log = require "log"

local st_utils = require "st.utils"

local CapEventHandlers = {}

CapEventHandlers.PlaybackStatus = {
  Buffering = "PLAYBACK_STATE_BUFFERING",
  Idle = "PLAYBACK_STATE_IDLE",
  Paused = "PLAYBACK_STATE_PAUSED",
  Playing = "PLAYBACK_STATE_PLAYING"
}

function CapEventHandlers.handle_player_volume(device, new_volume, is_muted)
  device:emit_event(capabilities.audioVolume.volume(new_volume))
  if is_muted then
    device:emit_event(capabilities.audioMute.mute.muted())
  else
    device:emit_event(capabilities.audioMute.mute.unmuted())
  end
end

function CapEventHandlers.handle_group_volume(device, new_volume, is_muted)
  device:emit_event(capabilities.mediaGroup.groupVolume(new_volume))
  if is_muted then
    device:emit_event(capabilities.mediaGroup.groupMute.muted())
  else
    device:emit_event(capabilities.mediaGroup.groupMute.unmuted())
  end
end

function CapEventHandlers.handle_group_update(device, group_info)
  local groupRole, groupPrimaryDeviceId, groupId = table.unpack(group_info)
  device:emit_event(capabilities.mediaGroup.groupRole(groupRole))
  device:emit_event(capabilities.mediaGroup.groupPrimaryDeviceId(groupPrimaryDeviceId))
  device:emit_event(capabilities.mediaGroup.groupId(groupId))
end

function CapEventHandlers.handle_audio_clip_status(device, clips)
  for _, clip in ipairs(clips) do
    if clip.status == "ACTIVE" then
      log.debug(st_utils.stringify_table(clip, "Playing Audio Clip: ", false))
    elseif clip.status == "DONE" then
      log.debug(st_utils.stringify_table(clip, "Completed Playing Audio Clip: ", false))
    end
  end
end

function CapEventHandlers.handle_playback_status(device, playback_state)
  if playback_state == CapEventHandlers.PlaybackStatus.Playing then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
  elseif playback_state == CapEventHandlers.PlaybackStatus.Idle then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  elseif playback_state == CapEventHandlers.PlaybackStatus.Paused then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
  elseif playback_state == CapEventHandlers.PlaybackStatus.Buffering then
    -- TODO the DTH doesn't currently do anything w/ buffering;
    -- might be worth figuring out what to do with this in the future.
    log.debug(string.format("Player [%s] buffering", device.label))
  end
end

function CapEventHandlers.update_favorites(device, new_favorites)
  device:emit_event(capabilities.mediaPresets.presets(new_favorites))
end

function CapEventHandlers.handle_playback_metadata_update(device, metadata_status_body)
  local audio_track_data = {}

  if metadata_status_body.container and metadata_status_body.container.type then
    local is_linein = string.find(metadata_status_body.container.type, "linein", 1, true) ~= nil
    local is_station = string.find(metadata_status_body.container.type, "station", 1, true) ~= nil
    local is_show = string.find(metadata_status_body.container.type, "show", 1, true) ~= nil
    local is_radio_tracklist = string.find(metadata_status_body.container.type, "trackList.program", 1, true) ~= nil

    if is_linein then
      audio_track_data.title = metadata_status_body.container.name
    end

    if metadata_status_body.container.service and metadata_status_body.container.service.name then
      audio_track_data.mediaSource = metadata_status_body.container.service.name
    elseif is_linein or is_station or is_show or is_radio_tracklist then
      audio_track_data.mediaSource = metadata_status_body.container.name
    end
  end

  local track_info = nil
  if metadata_status_body.track then
    track_info = metadata_status_body.track
  elseif metadata_status_body.currentItem and metadata_status_body.currentItem.track then
    track_info = metadata_status_body
        .currentItem.track
  end

  if track_info ~= nil then
    if track_info.album and track_info.album.name then
      audio_track_data.album = track_info.album.name
    end
    if track_info.artist and track_info.artist.name then
      audio_track_data.artist = track_info.artist.name
    end
    if track_info.imageUrl then
      audio_track_data.albumArtUrl = track_info.imageUrl
    end
    if track_info.name then
      audio_track_data.title = track_info.name
    end
    if track_info.service and track_info.service.name then
      audio_track_data.mediaSource = track_info.service.name
    end
  end

  if type(audio_track_data.title) == "string" then
    device:emit_event(capabilities.audioTrackData.audioTrackData(audio_track_data))
  end
end

return CapEventHandlers
