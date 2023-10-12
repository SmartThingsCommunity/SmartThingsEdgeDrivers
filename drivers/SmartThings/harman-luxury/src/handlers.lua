local capabilities = require "st.capabilities"
local api = require "api.apis"
local log = require "log"
local const = require "constants"

local Handler = {}

--- handler of switch.on
function Handler.handle_on(_, device, _)
  log.info("Starting handle_on")
  -- send API switch on message
  local ip = device:get_field(const.IP)
  local val, err = api.SetOn(ip)
  if val then
    device:emit_event(capabilities.switch.switch.on())
  else
    log.warn(string.format("Error during handle_on(): %s", err))
  end
end

--- handler of switch.off
function Handler.handle_off(_, device, _)
  log.info("Starting handle_off")
  -- send API switch off message
  local ip = device:get_field(const.IP)
  local val, err = api.SetOff(ip)
  if val then
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  else
    log.warn(string.format("Error during handle_off(): %s", err))
  end
end

--- internal function to set mute
---@param Device
---@param mute boolean
---@param func_name string
local function set_mute(device, mute, func_name)
  local ip = device:get_field(const.IP)
  local val, err = api.SetMute(ip, mute)
  if val then
    if mute then
      device:emit_event(capabilities.audioMute.mute.muted())
    else
      device:emit_event(capabilities.audioMute.mute.unmuted())
    end
  else
    log.warn(string.format("Error during %s(): %s", func_name, err))
  end
end

--- handler of audioMute.mute
function Handler.handle_mute(_, device, _)
  log.info("Starting handle_mute")
  -- send API mute on message
  set_mute(device, true, "handle_mute")
end

--- handler of audioMute.unmute
function Handler.handle_unmute(_, device, _)
  log.info("Starting handle_unmute")
  -- send API mute off message
  set_mute(device, false, "handle_unmute")
end

--- handler of audioMute.setMute
function Handler.handle_set_mute(_, device, cmd)
  log.info("Starting handle_set_mute")
  -- send API mute set message
  local mute = cmd.args and cmd.args.state == "muted"
  set_mute(device, mute, "handle_set_mute")
end

--- internal function to set volume
---@param device Device
---@param vol number|nil
---@param step number|nil
---@param func_name string
local function set_vol(device, vol, step, func_name)
  local ip = device:get_field(const.IP)
  local setVol
  if vol then
    setVol = vol
  else
    local currVol, err = api.GetVol(ip)
    if err or type(currVol) ~= "number" then
      currVol = device:get_latest_state("main", capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME)
    end
    setVol = currVol + step
  end
  local val, err = api.SetVol(ip, setVol)
  if val then
    device:emit_event(capabilities.audioVolume.volume(setVol))
  else
    log.warn(string.format("Error during %s(): %s", func_name, err))
  end
end

--- handler of audioVolume.volumeUp
function Handler.handle_volume_up(_, device, _)
  log.info("Starting handle_volume_up")
  -- send API volume get message to know to what volume to raise
  set_vol(device, nil, const.VOL_STEP, "handle_volume_up")
end

--- handler of audioVolume.volumeDown
function Handler.handle_volume_down(_, device, _)
  log.info("Starting handle_volume_down")
  -- send API volume get message to know to what volume to decrease
  set_vol(device, nil, -const.VOL_STEP, "handle_volume_down")
end

--- handler of audioVolume.setVolume
function Handler.handle_set_volume(_, device, cmd)
  log.info("Starting handle_set_volume")
  -- send API volume set message
  set_vol(device, cmd.args.volume, nil, "handle_set_volume")
end

--- handler of mediaInputSource.setInputSource
function Handler.handle_setInputSource(_, device, cmd)
  log.info("Starting handle_setInputSource")
  -- send API input source set message
  local ip = device:get_field(const.IP)
  local val, err = api.SetInputSource(ip, cmd.args.mode)
  if val then
    device:emit_event(capabilities.mediaInputSource.inputSource(cmd.args.mode))
  else
    log.warn(string.format("Error during handle_setInputSource(): %s", err))
  end
end

--- handler of mediaPresets.playPreset
function Handler.handle_play_preset(_, device, cmd)
  log.info("Starting handle_play_preset")
  -- send API to play media preset
  local ip = device:get_field(const.IP)
  local presetId = cmd.args.presetId:lower():gsub("preset", ""):gsub("%W", "")
  local mediaPresets = device:get_latest_state("main", capabilities.mediaPresets.ID,
                                               capabilities.mediaPresets.presets.NAME)
  for _, preset in pairs(mediaPresets) do
    local id = preset.id
    local name = preset.name:lower():gsub("preset", ""):gsub("%W", "")
    if id == presetId or name == presetId then
      local _, err = api.PlayMediaPreset(ip, id)
      if err then
        log.warn(string.format("Error during handle_play_preset(): %s", err))
      end
      return
    end
  end
  log.warn(string.format("Couldn't find provided Media Preset: %s", cmd.args.presetId))
end

--- handler of audioNotification.playTrack, audioNotification.playTrackAndResume,
--- and audioNotification.playTrackAndRestore
function Handler.handle_audio_notification(_, device, cmd)
  log.info("Starting handle_audio_notification")
  -- send API to play audio notification
  local ip = device:get_field(const.IP)
  local uri, level = cmd.args.uri, cmd.args.level
  local _, err = api.SendAudioNotification(ip, uri, level)
  if err then
    log.warn(string.format("Error during handle_audio_notification(): %s", err))
  end
end

--- internal function to handle set playback status
---@param device Device
---@param status string
---@param func_name string
local function set_playback_status(device, status, func_name)
  local invokeFunc = {
    pause = api.InvokePause,
    play = api.InvokePlay,
    stop = api.InvokeStop,
  }
  if invokeFunc[status] == nil then
    log.warn(string.format("Error during %s(): unsupported status given - %s", func_name, status))
    return
  else
    local ip = device:get_field(const.IP)
    local _, err = invokeFunc[status](ip)
    if err then
      log.warn(string.format("Error during %s(): %s", func_name, err))
    end
  end
end

--- handler of mediaPlayback.play
function Handler.handle_play(_, device, _)
  log.info("Starting handle_play")
  set_playback_status(device, "play", "handle_play")
end

--- handler of mediaPlayback.pause
function Handler.handle_pause(_, device, _)
  log.info("Starting handle_pause")
  set_playback_status(device, "pause", "handle_pause")
end

--- handler of mediaPlayback.stop
function Handler.handle_stop(_, device, _)
  log.info("Starting handle_stop")
  set_playback_status(device, "stop", "handle_stop")
end

--- handler of mediaTrackControl.nextTrack
function Handler.handle_next_track(_, device, _)
  log.info("Starting handle_next_track")
  local ip = device:get_field(const.IP)
  local _, err = api.InvokeNext(ip)
  if err then
    log.warn(string.format("Error during handle_next_track(): %s", err))
  end
end

--- handler of mediaTrackControl.previousTrack
function Handler.handle_previous_track(_, device, _)
  log.info("Starting handle_previous_track")
  local ip = device:get_field(const.IP)
  local _, err = api.InvokePrevious(ip)
  if err then
    log.warn(string.format("Error during handle_previous_track(): %s", err))
  end
end

--- handler of keypadInput.sendKey
function Handler.handle_send_key(_, device, cmd)
  log.info(string.format("Starting handle_send_key. Input key is: %s", cmd.args.keyCode))
  local ip = device:get_field(const.IP)
  local _, err = api.InvokeSendKey(ip, cmd.args.keyCode)
  if err then
    log.warn(string.format("Error during handle_send_key(): %s", err))
  end
end

return Handler
