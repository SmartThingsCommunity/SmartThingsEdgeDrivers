local log = require "log"
local PlayerFields = require "fields".SonosPlayerFields
local st_utils = require "st.utils"

--- Handle commands by constructing Sonos JSON payloads and emitting to the correct player. Sonos
--- commands are JSON that take the form of a 2-element array where the first index is the header
--- and the second index is the body. Hence the empty table in the second position.
---
--- https://developer.sonos.com/reference/control-api-examples-lan/
local CapCommandHandlers = {}

local QUEUE_ACTION_PREF = "queueAction"

local function _do_send(device, payload)
  local conn = device:get_field(PlayerFields.CONNECTION)
  if conn and conn:is_running() then
    conn:send_command(payload)
  else
    log.warn("No sonos connection for handling capability command")
  end
end

local function _do_send_to_group(driver, device, payload)
  local household_id, group_id = driver.sonos:get_group_for_device(device)
  payload[1].householdId = household_id
  payload[1].groupId = group_id

  _do_send(device, payload)
end

local function _do_send_to_self(driver, device, payload)
  local household_id, player_id = driver.sonos:get_player_for_device(device)
  payload[1].householdId = household_id
  payload[1].playerId = player_id

  _do_send(device, payload)
end

function CapCommandHandlers.handle_play(driver, device, _cmd)
  local payload = {
    { namespace = "playback", command = "play" }, {}
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_pause(driver, device, _cmd)
  local payload = {
    { namespace = "playback", command = "pause" }, {}
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_next_track(driver, device, _cmd)
  local payload = {
    { namespace = "playback", command = "skipToNextTrack" }, {}
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_previous_track(driver, device, _cmd)
  local payload = {
    { namespace = "playback", command = "skipToPreviousTrack" }, {}
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_mute(driver, device, _cmd)
  CapCommandHandlers.handle_set_mute(driver, device, { args = { state = "muted" } })
end

function CapCommandHandlers.handle_unmute(driver, device, _cmd)
  CapCommandHandlers.handle_set_mute(driver, device, { args = { state = "unmuted" } })
end

function CapCommandHandlers.handle_set_mute(driver, device, cmd)
  local set_mute = (cmd.args and cmd.args.state == "muted")
  local payload = {
    { namespace = "playerVolume", command = "setMute" },
    { muted = set_mute }
  }
  _do_send_to_self(driver, device, payload)
end

function CapCommandHandlers.handle_volume_up(driver, device, cmd)
  local payload = {
    { namespace = "playerVolume", command = "setRelativeVolume" },
    { volumeDelta = 5 }
  }
  _do_send_to_self(driver, device, payload)
end

function CapCommandHandlers.handle_volume_down(driver, device, cmd)
  local payload = {
    { namespace = "playerVolume", command = "setRelativeVolume" },
    { volumeDelta = -5 }
  }
  _do_send_to_self(driver, device, payload)
end

function CapCommandHandlers.handle_set_volume(driver, device, cmd)
  local new_volume = st_utils.clamp_value(cmd.args.volume, 0, 100)
  local payload = {
    { namespace = "playerVolume", command = "setVolume" },
    { volume = new_volume }
  }
  _do_send_to_self(driver, device, payload)
end

function CapCommandHandlers.handle_group_mute(driver, device, _cmd)
  CapCommandHandlers.handle_group_set_mute(driver, device, { args = { state = "muted" } })
end

function CapCommandHandlers.handle_group_unmute(driver, device, _cmd)
  CapCommandHandlers.handle_group_set_mute(driver, device, { args = { state = "unmuted" } })
end

function CapCommandHandlers.handle_group_set_mute(driver, device, cmd)
  local set_mute = (cmd.args and cmd.args.state == "muted")
  local payload = {
    { namespace = "groupVolume", command = "setMute" },
    { muted = set_mute }
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_group_volume_up(driver, device, cmd)
  local payload = {
    { namespace = "groupVolume", command = "setRelativeVolume" },
    { volumeDelta = 5 }
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_group_volume_down(driver, device, cmd)
  local payload = {
    { namespace = "groupVolume", command = "setRelativeVolume" },
    { volumeDelta = -5 }
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_group_set_volume(driver, device, cmd)
  local new_volume = st_utils.clamp_value(cmd.args.groupVolume, 0, 100)
  local payload = {
    { namespace = "groupVolume", command = "setVolume" },
    { volume = new_volume }
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_play_preset(driver, device, cmd)
  local payload = {
    { namespace = "favorites", command = "loadFavorite" },
    {
      favoriteId = cmd.args.presetId,
      playOnCompletion = true,
      action = (device.preferences[QUEUE_ACTION_PREF] or "APPEND")
    }
  }
  _do_send_to_group(driver, device, payload)
end

function CapCommandHandlers.handle_audio_notification(driver, device, cmd)
  local payload = {
    { namespace = "audioClip", command = "loadAudioClip" },
    {
      appId = "edge.smartthings.com",
      name = "SmartThings Audio Notification",
      streamUrl = cmd.args.uri,
    }
  }

  if type(cmd.args.level) == 'number' then
    payload[2].volume = cmd.args.level
  end
  _do_send_to_self(driver, device, payload)
end

return CapCommandHandlers
