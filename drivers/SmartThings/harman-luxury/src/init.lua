----------------------------------------------------------
-- Inclusions
----------------------------------------------------------
-- SmartThings inclusions
local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local socket = require "cosock.socket"
local st_utils = require "st.utils"
local log = require "log"

-- local Harman Luxury inclusions
local discovery = require "disco"
local handlers = require "handlers"
local api = require "api.apis"
local const = require "constants"

----------------------------------------------------------
-- Device Functions
----------------------------------------------------------

local function device_removed(driver, device)
    log.info("Device removed")
    local id = device.device_network_id
    driver.registered_devices[id] = nil
end

local function update_connection(device, device_dni, device_ip)
    log.debug("Entered update_connection()...")
    -- test if IP works by reading the UUID in the device if ip was provided
    if device_ip then
        local ret, mac = api.GetMAC(device_ip)
        if ret then
            local current_dni = mac:gsub("-", ""):gsub(":", ""):lower()
            if current_dni == device_dni then
                log.trace(string.format("update_connection for %s: IP haven't changed", device_dni))
                device:online()
                return
            end
        else
            log.trace(string.format(
                "update_connection for %s: IP changed or couldn't be reached. Trying to find the new IP", device_dni))

            -- look for device's new IP if it's still on network
            local devices_ip_table = nil
            for _ = 1, 10 do
                devices_ip_table = discovery.find_ip_table()
                if (devices_ip_table[device_dni]) then
                    break
                end
                socket.sleep(1)
            end
            local current_ip = devices_ip_table[device_dni]
            if (current_ip == nil) then
                log.info("Couldn't find device during refresh, hence setting device to offline")
                device:offline()
                return
            else
                device.set_field(const.IP, current_ip, {
                    persist = true
                })
                device:online()
            end
        end
    end
end

local function refresh(_, device)
    local ip = device:get_field(const.IP)

    -- check and update device status
    local ret, power_state
    ret, power_state = api.GetPowerState(ip)
    if ret then
        local player_state, trackdata, totalTime
        log.debug(string.format("Current power state: %s", power_state))

        if power_state == "online" then
            device:emit_event(capabilities.switch.switch.on())
            ret, player_state = api.GetPlayerState(ip)
            if ret then
                if player_state == "playing" then
                    device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
                elseif player_state == "paused" then
                    device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
                else
                    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
                end
            end

            -- get audio track data
            ret, trackdata, totalTime = api.getAudioTrackData(ip)
            if ret then
                device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
                device:emit_event(capabilities.audioTrackData.totalTime(totalTime or 0))
            end
        else
            device:emit_event(capabilities.switch.switch.off())
            device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
        end
    end

    -- check and update device volume and mute status
    local vol, mute
    ret, vol = api.GetVol(ip)
    if ret then
        device:emit_event(capabilities.audioVolume.volume(vol))
    end
    ret, mute = api.GetMute(ip)
    if ret then
        if mute then
            device:emit_event(capabilities.audioMute.mute.muted())
        else
            device:emit_event(capabilities.audioMute.mute.unmuted())
        end
    end

    -- check and update device media input source
    local inputSource
    ret, inputSource = api.GetInputSource(ip)
    if ret then
        device:emit_event(capabilities.mediaInputSource.inputSource(inputSource))
    end
end

local function check_for_updates(device)
    log.trace(string.format("%s, checking if device values changed", device.device_network_id))
    local ip = device:get_field(const.IP)
    local ret, changes = api.InvokeGetUpdates(ip)
    if ret then
        log.debug(string.format("changes: %s", st_utils.stringify_table(changes)))
        if type(changes) ~= "table" then
            log.warn("check_for_updates: Received value was not a table (JSON). Likely an error occured")
            return
        end
        -- check if there are any changes
        local next = next
        if next(changes) ~= nil then
            -- check for a power state change
            if changes["powerState"] then
                local powerState = changes["powerState"]
                if powerState == "online" then
                    device:emit_event(capabilities.switch.switch.on())
                elseif powerState == "offline" then
                    device:emit_event(capabilities.switch.switch.off())
                end
            end
            -- check for a player state change
            if changes["playerState"] then
                local playerState = changes["playerState"]
                if playerState == "playing" then
                    device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
                elseif playerState == "paused" then
                    log.debug("playerState - changed to paused")
                    device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
                else
                    device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
                end
            end
            -- check for a audio track data change
            if changes["audioTrackData"] then
                local audioTrackData = changes["audioTrackData"]
                local trackdata = {}
                if type(audioTrackData.title) == "string" then
                    trackdata.title = audioTrackData.title
                end
                if type(audioTrackData.artist) == "string" then
                    trackdata.artist = audioTrackData.artist
                end
                if type(audioTrackData.album) == "string" then
                    trackdata.album = audioTrackData.album
                end
                if type(audioTrackData.albumArtUrl) == "string" then
                    trackdata.albumArtUrl = audioTrackData.albumArtUrl
                end
                if type(audioTrackData.mediaSource) == "string" then
                    trackdata.mediaSource = audioTrackData.mediaSource
                end
                -- if track changed
                device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
                device:emit_event(capabilities.audioTrackData.totalTime(audioTrackData.totalTime or 0))
            end
            -- check for a media input source change
            if changes["mediaInputSource"] then
                device:emit_event(capabilities.mediaInputSource.inputSource(changes["mediaInputSource"]))
            end
            -- check for a volume value change
            if changes["volume"] then
                device:emit_event(capabilities.audioVolume.volume(changes["volume"]))
            end
            -- check for a mute value change
            if changes["mute"] ~= nil then
                if changes["mute"] then
                    device:emit_event(capabilities.audioMute.mute.muted())
                else
                    device:emit_event(capabilities.audioMute.mute.unmuted())
                end
            end
        end
    end
end

local function create_check_for_updates_thread(device)
    local old_timer = device:get_field(const.UPDATE_TIMER)
    if old_timer ~= nil then
        log.info(string.format("create_check_for_updates_thread: dni=%s, remove old timer", device.device_network_id))
        device.thread:cancel_timer(old_timer)
    end

    log.info(string.format("create_check_for_updates_thread: dni=%s", device.device_network_id))
    local new_timer = device.thread:call_on_schedule(const.UPDATE_INTERVAL, function()
        check_for_updates(device)
    end, "value_updates_timer")
    device:set_field(const.UPDATE_TIMER, new_timer)
end

local function create_check_health_thread(device)
    local device_dni = device.device_network_id
    local device_ip = device:get_field(const.IP)
    local old_timer = device:get_field(const.HEALTH_TIMER)
    if old_timer ~= nil then
        log.info(string.format("create_check_health_thread: dni=%s, remove old timer", device_dni))
        device.thread:cancel_timer(old_timer)
    end

    log.info(string.format("create_check_health_thread: dni=%s", device_dni))
    local new_timer = device.thread:call_on_schedule(const.HEALTH_CHEACK_INTERVAL, function()
        update_connection(device, device_dni, device_ip)
    end, "value_health_timer")
    device:set_field(const.HEALTH_TIMER, new_timer)
end

local function device_init(driver, device)
    log.info(string.format("Initiating device: %s", device.label))

    -- set supported media playback commands
    device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
        {capabilities.mediaPlayback.commands.play.NAME, capabilities.mediaPlayback.commands.pause.NAME,
         capabilities.mediaPlayback.commands.stop.NAME}))
    device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
        {capabilities.mediaTrackControl.commands.nextTrack.NAME,
         capabilities.mediaTrackControl.commands.previousTrack.NAME}))

    -- set supported input sources
    device:emit_event(capabilities.mediaInputSource.supportedInputSources(
        {"HDMI", "aux", "bluetooth", "digital", "wifi"}))

    -- set supported keypad inputs
    device:emit_event(capabilities.keypadInput.supportedKeyCodes(
        {"UP", "DOWN", "LEFT", "RIGHT", "SELECT", "BACK", "EXIT", "MENU", "SETTINGS", "HOME", "NUMBER0", "NUMBER1",
         "NUMBER2", "NUMBER3", "NUMBER4", "NUMBER5", "NUMBER6", "NUMBER7", "NUMBER8", "NUMBER9"}))

    local device_dni = device.device_network_id

    local device_ip = device:get_field(const.IP)
    if not device_ip then
        device_ip = driver.registered_devices[device_dni]
    end
    log.trace(string.format("device IP: %s", device_ip))

    create_check_health_thread(device)
    create_check_for_updates_thread(device)

    update_connection(device, device_dni, device_ip)
    refresh(driver, device)
end

local function device_added(driver, device)
    log.info(string.format("Device added: %s", device.label))
    discovery.set_device_field(driver, device)
    -- ensuring device is initialised
    device_init(driver, device)
end

local function device_changeInfo(_, device, _, _)
    log.info(string.format("Device added: %s", device.label))
    local ip = device:get_field(const.IP)
    if not ip then
        log.warn("Failed to get device ip during device_changeInfo()")
        update_connection(device, device.device_network_id, nil)
    else
        local ret, val = api.SetDeviceName(ip, device.label)
        if not ret then
            log.info(string.format(
                "device_changeInfo: Error occured during attempt to change device name. Error message: %s", val))
        end
    end
end

local function do_refresh(driver, device, _)
    log.info(string.format("Starting do_refresh: %s", device.label))

    -- check and update device IP
    local dni = device.device_network_id
    local ip = device:get_field(const.IP)
    update_connection(device, dni, ip)

    -- check and update device values
    refresh(driver, device)
end

----------------------------------------------------------
-- Driver Definition
----------------------------------------------------------

--- @type Driver
local driver = Driver("Harman Luxury", {
    discovery = discovery.discovery_handler,
    lifecycle_handlers = {
        init = device_init,
        added = device_added,
        removed = device_removed,
        infoChanged = device_changeInfo
    },
    capability_handlers = {
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = do_refresh
        },
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = handlers.handle_on,
            [capabilities.switch.commands.off.NAME] = handlers.handle_off
        },
        [capabilities.audioMute.ID] = {
            [capabilities.audioMute.commands.mute.NAME] = handlers.handle_mute,
            [capabilities.audioMute.commands.unmute.NAME] = handlers.handle_unmute,
            [capabilities.audioMute.commands.setMute.NAME] = handlers.handle_set_mute
        },
        [capabilities.audioVolume.ID] = {
            [capabilities.audioVolume.commands.volumeUp.NAME] = handlers.handle_volume_up,
            [capabilities.audioVolume.commands.volumeDown.NAME] = handlers.handle_volume_down,
            [capabilities.audioVolume.commands.setVolume.NAME] = handlers.handle_set_volume
        },
        [capabilities.mediaInputSource.ID] = {
            [capabilities.mediaInputSource.commands.setInputSource.NAME] = handlers.handle_setInputSource
        },
        [capabilities.audioNotification.ID] = {
            [capabilities.audioNotification.commands.playTrack.NAME] = handlers.handle_audio_notification,
            [capabilities.audioNotification.commands.playTrackAndResume.NAME] = handlers.handle_audio_notification,
            [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = handlers.handle_audio_notification
        },
        [capabilities.mediaPlayback.ID] = {
            [capabilities.mediaPlayback.commands.pause.NAME] = handlers.handle_play,
            [capabilities.mediaPlayback.commands.play.NAME] = handlers.handle_pause,
            [capabilities.mediaPlayback.commands.stop.NAME] = handlers.handle_stop
        },
        [capabilities.mediaTrackControl.ID] = {
            [capabilities.mediaTrackControl.commands.nextTrack.NAME] = handlers.handle_next_track,
            [capabilities.mediaTrackControl.commands.previousTrack.NAME] = handlers.handle_previous_track
        },
        [capabilities.keypadInput.ID] = {
            [capabilities.keypadInput.commands.sendKey.NAME] = handlers.handle_send_key
        }
    },
    supported_capabilities = {capabilities.switch, capabilities.audioMute, capabilities.audioVolume,
                              capabilities.mediaPlayback, capabilities.mediaTrackControl, capabilities.keypadInput},
    registered_devices = {}
})

----------------------------------------------------------
-- main
----------------------------------------------------------

log.info("Starting Harman Luxury run loop")
driver:run()
log.info("Exiting Harman Luxury run loop")
