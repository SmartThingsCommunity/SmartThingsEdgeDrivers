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
local MANUFACTURE_NAME_PATH = "settings:/system/manufacturer"
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

APIs = {}

--- system APIs ------------------------------------------

--- get UUID from Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetUUID(ip)
    return get.String(ip, UUID_PATH)
end

--- get MAC address from Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetMAC(ip)
    return get.String(ip, MAC_PATH)
end

--- get Member ID from Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetMemberId(ip)
    return get.String(ip, MEMBER_ID_PATH)
end

--- get device manufacture name from Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetManufatureName(ip)
    return get.String(ip, MANUFACTURE_NAME_PATH)
end

--- get device name from Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetDeviceName(ip)
    return get.String(ip, DEVICE_NAME_PATH)
end

--- get model name from Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetModelName(ip)
    return get.String(ip, MODEL_NAME_PATH)
end

--- get product name from Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetProductName(ip)
    return get.String(ip, PRODUCT_NAME_PATH)
end

--- set product name from Harman Luxury on ip
---@param ip string
---@param value string
---@return boolean, string|table
function APIs.SetDeviceName(ip, value)
    return set.String(ip, DEVICE_NAME_PATH, value)
end

--- power manager APIs -----------------------------------

--- invoke smartthings:setOn on ip
---@param ip string
---@return boolean, string|table
function APIs.SetOn(ip)
    return invoke.Activate(ip, SMARTTHINGS_PATH .. "setOn")
end

--- invoke smartthings:setOff on ip
---@param ip string
---@return boolean, string|table
function APIs.SetOff(ip)
    return invoke.Activate(ip, SMARTTHINGS_PATH .. "setOff")
end

--- get current power state Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetPowerState(ip)
    return invoke.Activate(ip, SMARTTHINGS_PATH .. "powerStatus")
end

--- audio APIs ------------------------------------

--- set Mute value of Harman Luxury media player on ip
---@param ip string
---@param value boolean
---@return boolean, string|table
function APIs.SetMute(ip, value)
    return set.Bool(ip, SMARTTHINGS_AUDIO_PATH .. "mute", value)
end

--- get Mute value of Harman Luxury media player on ip
---@param ip string
---@return boolean, string|table
function APIs.GetMute(ip)
    return get.Bool(ip, SMARTTHINGS_AUDIO_PATH .. "mute")
end

--- set Volume value of Harman Luxury media player on ip
---@param ip string
---@param value integer
---@return boolean, string|table
function APIs.SetVol(ip, value)
    return set.I32(ip, SMARTTHINGS_AUDIO_PATH .. "volume", value)
end

--- get Volume value of Harman Luxury media player on ip
---@param ip string
---@return boolean, string|table
function APIs.GetVol(ip)
    return get.I32(ip, SMARTTHINGS_AUDIO_PATH .. "volume")
end

--- invoke smartthings:audio/getAudioTrackData on ip
---@param ip string
---@return table|nil, number|nil, number|nil
function APIs.getAudioTrackData(ip)
    local ret, val = invoke.Activate(ip, SMARTTHINGS_AUDIO_PATH .. "getAudioTrackData")
    if ret then
        local trackdata = {
            title = val.title,
            artist = val.artist,
            album = val.album,
            albumArtUrl = val.albumArtUrl,
            mediaSource = val.mediaSource
        }
        local totalTime = val.totalTime
        local elapsedTime = val.elapsedTime
        return trackdata, totalTime, elapsedTime
    else
        return nil, nil, nil
    end
end

--- Audio Notification API ------------------------------------

--- invoke Audio Notification of Harman Luxury on ip
---@param ip string
---@param uri string
---@param level number
---@return boolean, string|table
function APIs.SendAudioNotification(ip, uri, level)
    local value = {
        SmartThingsAudioNotification = {
            uri = uri,
            level = level
        }
    }
    return invoke.ActivateValue(ip, SMARTTHINGS_PATH .. "playAudioNotification", value)
end

--- media player APIs ------------------------------------

--- set Input Source value of Harman Luxury on ip
---@param ip string
---@param value integer
---@return boolean, string|table
function APIs.SetInputSource(ip, source)
    local value = {
        string_ = source
    }
    return invoke.ActivateValue(ip, SMARTTHINGS_MEDIA_PATH .. "setInputSource", value)
end

--- get Input Source value of Harman Luxury on ip
---@param ip string
---@return boolean, string|table
function APIs.GetInputSource(ip)
    return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "getInputSource")
end

--- invoke smartthings:media/setPlayPause on ip
---@param ip string
---@return boolean, string|table
function APIs.InvokePlayPause(ip)
    return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setPlayPause")
end

--- invoke smartthings:media/setNextTrack on ip
---@param ip string
---@return boolean, string|table
function APIs.InvokeNext(ip)
    return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setNextTrack")
end

--- invoke smartthings:media/setPrevTrack on ip
---@param ip string
---@return boolean, string|table
function APIs.InvokePrevious(ip)
    return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setPrevTrack")
end

--- invoke smartthings:media/setStop on ip
---@param ip string
---@return boolean, string|table
function APIs.InvokeStop(ip)
    return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "setStop")
end

--- invoke smartthings:media/setStop on ip
---@param ip string
---@return boolean, string|table
function APIs.GetPlayerState(ip)
    return invoke.Activate(ip, SMARTTHINGS_MEDIA_PATH .. "getPlayerState")
end

--- key input APIs ------------------------------------

--- invoke smartthings:sendKey on ip
---@param ip string
---@param key string
---@return boolean, string|table
function APIs.InvokeSendKey(ip, key)
    local value = {
        NsdkSmartThingsKey = key
    }
    return invoke.ActivateValue(ip, SMARTTHINGS_PATH .. "sendKey", value)
end

--- check for values change APIs ------------------------------------

--- invoke smartthings:updateValues on ip
---@param ip string
---@return boolean, string|table
function APIs.InvokeGetUpdates(ip)
    return invoke.Activate(ip, SMARTTHINGS_PATH .. "updateValues")
end

return APIs
