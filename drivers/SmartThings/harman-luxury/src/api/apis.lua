local get = require "api.gets"
local set = require "api.sets"
local invoke = require "api.invokes"

----------------------------------------------------------
--- Definitions
----------------------------------------------------------

--- system paths -----------------------------------------

local UUID_PATH = "settings:/system/memberId"
local MAC_PATH = "settings:/system/primaryMacAddress"
local MEMBER_ID_PATH = "settings:/system/memberId"
local MANUFACTURER_NAME_PATH = "settings:/system/manufacturer"
local DEVICE_NAME_PATH = "settings:/deviceName"
local MODEL_NAME_PATH = "settings:/system/modelName"
local PRODUCT_NAME_PATH = "settings:/system/productName"

--- SmartThings paths ----------------------------------
local SMARTTHINGS_PATH = "smartthings:"
local SMARTTHINGS_AUDIO_PATH = "smartthings:audio/"
local SMARTTHINGS_MEDIA_PATH = "smartthings:media/"

----------------------------------------------------------
--- APIs
----------------------------------------------------------

local APIs = {}

--- system APIs ------------------------------------------

--- get UUID from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetUUID(ip)
  return get.String(ip, UUID_PATH)
end

--- get MAC address from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetMAC(ip)
  return get.String(ip, MAC_PATH)
end

--- get Member ID from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetMemberId(ip)
  return get.String(ip, MEMBER_ID_PATH)
end

--- get device manufacturer name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetManufacturerName(ip)
  return get.String(ip, MANUFACTURER_NAME_PATH)
end

--- get device name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetDeviceName(ip)
  return get.String(ip, DEVICE_NAME_PATH)
end

--- get model name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetModelName(ip)
  return get.String(ip, MODEL_NAME_PATH)
end

--- get product name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetProductName(ip)
  return get.String(ip, PRODUCT_NAME_PATH)
end

--- set product name from Harman Luxury on ip
---@param ip string
---@param value string
---@return boolean|number|string|table|nil, nil|string
function APIs.SetDeviceName(ip, value)
  return set.String(ip, DEVICE_NAME_PATH, value)
end

--- get active credential token from a Harman Luxury device on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.InitCredentialsToken(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "initCredentialsToken")
end

--- get active credential token from a Harman Luxury device on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.GetCredentialsToken(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "getCredentialsToken")
end

--- get supported input sources from a Harman Luxury device on ip
---@param ip string
---@return table|nil, nil|string
function APIs.GetSupportedInputSources(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "getSupportedInputSources")
end

--- power manager APIs -----------------------------------

--- invoke smartthings:setOn on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.SetOn(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "setOn")
end

--- invoke smartthings:setOff on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.SetOff(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "setOff")
end

--- get current power state Harman Luxury on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.GetPowerState(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "powerStatus")
end

--- audio APIs ------------------------------------

--- set Mute value of Harman Luxury media player on ip
---@param ip string
---@param value boolean
---@return boolean|number|string|table|nil, nil|string
function APIs.SetMute(ip, value)
  return set.Bool(ip, SMARTTHINGS_AUDIO_PATH .. "mute", value)
end

--- get Mute value of Harman Luxury media player on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.GetMute(ip)
  return get.Bool(ip, SMARTTHINGS_AUDIO_PATH .. "mute")
end

--- set Volume value of Harman Luxury media player on ip
---@param ip string
---@param value integer
---@return boolean|number|string|table|nil, nil|string
function APIs.SetVol(ip, value)
  return set.I32(ip, SMARTTHINGS_AUDIO_PATH .. "volume", value)
end

--- get Volume value of Harman Luxury media player on ip
---@param ip string
---@return number|nil, nil|string
function APIs.GetVol(ip)
  return get.I32(ip, SMARTTHINGS_AUDIO_PATH .. "volume")
end

--- invoke smartthings:audio/getAudioTrackData on ip
---@class AudioTrackData
---@field trackdata table<string>
---@field supportedPlaybackCommands table<string>
---@field supportedTrackControlCommands table<string>
---@field totalTime number
---@param ip string
---@return AudioTrackData|nil, nil|string
function APIs.getAudioTrackData(ip)
  local val, err = invoke.Activate(ip, SMARTTHINGS_AUDIO_PATH .. "getAudioTrackData")
  if val then
    local audioTrackData = {
      trackdata = {
        title = val.title or "",
        artist = val.artist or nil,
        album = val.album or nil,
        albumArtUrl = val.albumArtUrl or nil,
        mediaSource = val.mediaSource or nil,
      },
      supportedPlaybackCommands = val.supportedPlaybackCommands,
      supportedTrackControlCommands = val.supportedTrackControlCommands,
      totalTime = val.totalTime,
    }
    return audioTrackData, nil
  else
    return nil, err
  end
end

--- Audio Notification API ------------------------------------

--- invoke Audio Notification of Harman Luxury on ip
---@param ip string
---@param uri string
---@param level number
---@return boolean|number|string|table|nil, nil|string
function APIs.SendAudioNotification(ip, uri, level)
  local value = {
    smartthingsAudioNotification = {
      uri = uri,
      level = level,
    },
  }
  return invoke.ActivateValue(ip, SMARTTHINGS_PATH .. "playAudioNotification", value)
end

--- media player APIs ------------------------------------

--- set Input Source value of Harman Luxury on ip
---@param ip string
---@param source string
---@return boolean|number|string|table|nil, nil|string
function APIs.SetInputSource(ip, source)
  local value = {
    string_ = source,
  }
  return invoke.ActivateValue(ip, SMARTTHINGS_MEDIA_PATH .. "setInputSource", value)
end

--- get Input Source value of Harman Luxury on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.GetInputSource(ip)
  return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "getInputSource")
end

--- play Media Preset with given id value on Harman Luxury on ip
---@param ip string
---@param id integer
---@return boolean|number|string|table|nil, nil|string
function APIs.PlayMediaPreset(ip, id)
  local value = {
    i32_ = id,
  }
  return invoke.ActivateValue(ip, SMARTTHINGS_MEDIA_PATH .. "playMediaPreset", value)
end

--- get Media Preset list of Harman Luxury on ip
---@param ip string
---@return table|nil, nil|string
function APIs.GetMediaPresets(ip)
  local val, err = invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "getMediaPresets")
  if val then
    return val.presets, nil
  else
    return nil, err
  end
end

--- invoke smartthings:media/setPlay on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.InvokePlay(ip)
  return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setPlay")
end

--- invoke smartthings:media/setPause on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.InvokePause(ip)
  return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setPause")
end

--- invoke smartthings:media/setNextTrack on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.InvokeNext(ip)
  return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setNextTrack")
end

--- invoke smartthings:media/setPrevTrack on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.InvokePrevious(ip)
  return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setPrevTrack")
end

--- invoke smartthings:media/setStop on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.InvokeStop(ip)
  return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setStop")
end

--- invoke smartthings:media/setStop on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.GetPlayerState(ip)
  return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "getPlayerState")
end

--- key input APIs ------------------------------------

--- invoke smartthings:sendKey on ip
---@param ip string
---@param key string
---@return boolean|number|string|table|nil, nil|string
function APIs.InvokeSendKey(ip, key)
  local value = {
    NsdkSmartThingsKey = key,
  }
  return invoke.ActivateValue(ip, SMARTTHINGS_PATH .. "sendKey", value)
end

--- check for values change APIs ------------------------------------

--- invoke smartthings:updateValues on ip
---@param ip string
---@return table|nil, nil|string
function APIs.InvokeGetUpdates(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "updateValues")
end

return APIs
