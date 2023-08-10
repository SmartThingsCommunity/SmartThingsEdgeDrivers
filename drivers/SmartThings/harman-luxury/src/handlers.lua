local capabilities = require "st.capabilities"
local api = require "api.apis"
local log = require "log"

local Handler = {}

--- handler of switch.on
---@param driver Driver
---@param device Device
---@param cmd function|nil
function Handler.handle_on(driver, device, cmd)
    log.info("Starting handle_on")
    -- send API switch on message
    local ip = device:get_field("device_ipv4")
    local ret = api.SetOn(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_on(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetPowerState(ip)
    if ret == "online" then
        device:emit_event(capabilities.switch.switch.on())
    else
        device:emit_event(capabilities.switch.switch.off())
    end
end

--- handler of switch.off
---@param driver Driver
---@param device Device
---@param cmd function|nil
function Handler.handle_off(driver, device, cmd)
    log.info("Starting handle_off")
    -- send API switch off message
    local ip = device:get_field("device_ipv4")
    local ret = api.SetOff(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_off(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetPowerState(ip)
    if ret == "online" then
        device:emit_event(capabilities.switch.switch.on())
    else
        device:emit_event(capabilities.switch.switch.off())
    end
end

function Handler.handle_mute(driver, device, cmd)
    log.info("Starting handle_mute")
    -- send API mute on message
    local ip = device:get_field("device_ipv4")
    local ret = api.Mute(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_mute(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetMute(ip)
    if ret then
        device:emit_event(capabilities.audioMute.mute.muted())
    else
        device:emit_event(capabilities.audioMute.mute.unmuted())
    end
end

function Handler.handle_unmute(driver, device, cmd)
    log.info("Starting handle_unmute")
    -- send API mute off message
    local ip = device:get_field("device_ipv4")
    local ret = api.Unmute(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_unmute(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetMute(ip)
    if ret then
        device:emit_event(capabilities.audioMute.mute.muted())
    else
        device:emit_event(capabilities.audioMute.mute.unmuted())
    end
end

function Handler.handle_set_mute(driver, device, cmd)
    log.info("Starting handle_set_mute")
    -- send API mute set message
    local ip = device:get_field("device_ipv4")
    local mute = cmd.args and cmd.args.state == "muted"
    local ret = api.SetMute(ip, mute)
    if type(ret) == "table" then
        log.warn("Error during handle_set_mute(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetMute(ip)
    if ret then
        device:emit_event(capabilities.audioMute.mute.muted())
    else
        device:emit_event(capabilities.audioMute.mute.unmuted())
    end
end

function Handler.handle_volume_up(driver, device, cmd)
    log.info("Starting handle_volume_up")
    -- send API volume get message to know to what volume to raise
    local ip = device:get_field("device_ipv4")
    local ret = api.VolUp(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_volume_up(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetVol(ip)
    device:emit_event(capabilities.audioVolume.volume(ret))
end

function Handler.handle_volume_down(driver, device, cmd)
    log.info("Starting handle_volume_down")
    -- send API volume get message to know to what volume to decrease
    local ip = device:get_field("device_ipv4")
    local ret = api.VolDown(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_volume_down(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetVol(ip)
    device:emit_event(capabilities.audioVolume.volume(ret))
end

function Handler.handle_set_volume(driver, device, cmd)
    log.info("Starting handle_set_volume")
    -- send API volume set message
    local ip = device:get_field("device_ipv4")
    local ret = api.SetVol(ip, cmd.args.volume)
    if type(ret) == "table" then
        log.warn("Error during handle_set_volume(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetVol(ip)
    device:emit_event(capabilities.audioVolume.volume(ret))
end

function Handler.handle_setInputSource(driver, device, cmd)
    log.info("Starting handle_setInputSource")
    -- send API input source set message
    local ip = device:get_field("device_ipv4")
    local ret = api.SetInputSource(ip, cmd.args.mode)
    if type(ret) == "table" then
        log.warn("Error during handle_setInputSource(): " .. ret["error"])
    end
    device:emit_event(capabilities.mediaInputSource.inputSource(cmd.args.mode))
    -- waiting for internal implementation
    -- -- verify change and update app
    -- local ret = api.GetInputSource(ip)
    -- device:emit_event(capabilities.mediaInputSource.inputSource(ret))
end

function Handler.handle_playPause(driver, device, cmd)
    log.info("Starting handle_playPause")
    local ip = device:get_field("device_ipv4")
    local ret = api.InvokePlayPause(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_playPause(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetPlayerState(ip)
    if ret == "playing" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
    elseif ret == "paused" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
    elseif ret == "stopped" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    end
end

function Handler.handle_stop(driver, device, cmd)
    log.info("Starting handle_stop")
    local ip = device:get_field("device_ipv4")
    local ret = api.InvokeStop(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_stop(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetPlayerState(ip)
    if ret == "playing" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
    elseif ret == "paused" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
    elseif ret == "stopped" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    end
end

function Handler.handle_set_playback_status(driver, device, cmd)
    log.info("Starting handle_set_playback_status")
    local ip = device:get_field("device_ipv4")
    local ret
    if cmd.args.status == "paused" then
        ret = api.InvokePlayPause(ip)
    elseif cmd.args.status == "playing" then
        ret = api.InvokePlayPause(ip)
    elseif cmd.args.status == "stopped" then
        ret = api.InvokeStop(ip)
    else
        log.warn("Error during handle_set_playback_status(): Unsupported status value")
    end
    if type(ret) == "table" then
        log.warn("Error during handle_stop(): " .. ret["error"])
    end
    -- verify change and update app
    local ret = api.GetPlayerState(ip)
    if ret == "playing" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
    elseif ret == "paused" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
    elseif ret == "stopped" then
        device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    end
end

function Handler.handle_next_track(driver, device, cmd)
    log.info("Starting handle_next_track")
    local ip = device:get_field("device_ipv4")
    local ret = api.InvokeNext(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_next_track(): " .. ret["error"])
    end
end

function Handler.handle_previous_track(driver, device, cmd)
    log.info("Starting handle_previous_track")
    local ip = device:get_field("device_ipv4")
    local ret = api.InvokePrevious(ip)
    if type(ret) == "table" then
        log.warn("Error during handle_previous_track(): " .. ret["error"])
    end
end

function Handler.handle_send_key(driver, device, cmd)
    log.info(string.format("Starting handle_send_key. Input key is: %s", cmd.args.keyCode))
    local ip = device:get_field("device_ipv4")
    local ret = api.InvokeSendKey(ip, cmd.args.keyCode)
    if type(ret) == "table" then
        log.warn("Error during handle_send_key(): " .. ret["error"])
    end
end

return Handler
