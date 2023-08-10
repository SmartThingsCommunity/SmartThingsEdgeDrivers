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

-- local variables
local UPDATE_INTERVAL = 1         -- in seconds
local HEALTH_CHEACK_INTERVAL = 10 -- in seconds

----------------------------------------------------------
-- Device Functions
----------------------------------------------------------

local function device_removed(driver, device)
    log.info("Device removed")
    local id = device.device_network_id
    driver.registered_devices[id] = nil
end

local function update_connection(driver, device, device_dni, device_ip)
    log.debug("Entered update_connection()...")
    -- test if IP works by reading the UUID in the device if ip was provided
    if device_ip then
        local mac = api.GetMAC(device_ip)
        local current_dni = mac:gsub("-", ""):gsub(":", ""):lower()
        if current_dni == device_dni then
            log.trace(string.format("update_connection for %s: IP haven't changed", device_dni))
            device:online()
            return
        else
            log.trace(string.format(
                "update_connection for %s: IP changed or couldn't be reached. Trying to find the new IP", device_dni))

            -- look for device's new IP if it's still on network
            local devices_ip_table = nil
            for i = 1, 10 do
                devices_ip_table = discovery.find_ip_table(driver)
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
                device.set_field("device_ipv4", current_ip, {
                    persist = true
                })
                device:online()
            end
        end
    end
end

local function refresh(driver, device)
    local dni = device.device_network_id
    local ip = device:get_field("device_ipv4")

    -- check and update device status
    local power_state = api.GetPowerState(ip)
    log.debug(string.format("Current power state: %s", power_state))

    if power_state == "online" then
        device:emit_event(capabilities.switch.switch.on())
        local player_state = api.GetPlayerState(ip)
        if player_state == "playing" then
            -- get audio track data
            local trackdata, totalTime, elapsedTime = api.getAudioTrackData(ip)
            device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
            device:emit_event(capabilities.audioTrackData.totalTime(totalTime or 0))
            device:emit_event(capabilities.audioTrackData.elapsedTime(elapsedTime or 0))
            device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
        elseif player_state == "paused" then
            -- get audio track data
            local trackdata, totalTime, elapsedTime = api.getAudioTrackData(ip)
            device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
            device:emit_event(capabilities.audioTrackData.totalTime(totalTime or 0))
            device:emit_event(capabilities.audioTrackData.elapsedTime(elapsedTime or 0))
            device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
        elseif player_state == "stopped" then
            device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
        end

        device:online()
    else
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
        device:offline()
    end

    -- check and update device volume and mute status
    local vol = api.GetVol(ip)
    local mute = api.GetMute(ip)
    device:emit_event(capabilities.audioVolume.volume(vol))
    if mute then
        device:emit_event(capabilities.audioMute.mute.muted())
    else
        device:emit_event(capabilities.audioMute.mute.unmuted())
    end

    -- pseudo initialisation of input source
    device:emit_event(capabilities.mediaInputSource.inputSource("wifi"))
end

local function check_for_updates(driver, device)
    log.trace(string.format("%s, checking if device values changed", device.device_network_id))
    local ip = device:get_field("device_ipv4")
    local changes = api.InvokeGetUpdates(ip)
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
                device:online()
            elseif powerState == "offline" then
                device:emit_event(capabilities.switch.switch.off())
                device:offline()
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
            elseif playerState == "stopped" then
                device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
            end
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

    -- if player is playing (not stopped) get audio track info
    local isStopped = device:get_latest_state("main", capabilities.mediaPlayback.ID,
        capabilities.mediaPlayback.playbackStatus.NAME) == "stopped"
    if not isStopped then
        -- get audio track data
        local trackdata, totalTime, elapsedTime = api.getAudioTrackData(ip)
        device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
        device:emit_event(capabilities.audioTrackData.totalTime(totalTime or 0))
        device:emit_event(capabilities.audioTrackData.elapsedTime(elapsedTime or 0))
        -- log.debug(string.format("check_for_updates: track values: %s", st_utils.stringify_table(trackdata)))
    end
end

local function create_check_for_updates_thread(driver, device)
    local old_timer = device:get_field("value_updates_timer")
    if old_timer ~= nil then
        log.info("create_check_for_updates_thread: dni=" .. device.device_network_id .. ", remove old timer")
        device.thread:cancel_timer(old_timer)
    end

    log.info("create_check_for_updates_thread: dni=" .. device.device_network_id)
    local new_timer = device.thread:call_on_schedule(UPDATE_INTERVAL, function()
        check_for_updates(driver, device)
    end, "value_updates_timer")
    device:set_field("value_updates_timer", new_timer)
end

local function create_check_health_thread(driver, device)
    local device_dni = device.device_network_id
    local device_ip = device:get_field("device_ipv4")
    local old_timer = device:get_field("value_health_timer")
    if old_timer ~= nil then
        log.info("create_check_health_thread: dni=" .. device_dni .. ", remove old timer")
        device.thread:cancel_timer(old_timer)
    end

    log.info("create_check_health_thread: dni=" .. device_dni)
    local new_timer = device.thread:call_on_schedule(HEALTH_CHEACK_INTERVAL, function()
        update_connection(driver, device, device_dni, device_ip)
    end, "value_health_timer")
    device:set_field("value_health_timer", new_timer)
end

local function device_init(driver, device)
    log.info(string.format("Initiating device: %s", device.label))

    -- set supported media playback commands
    device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
        { capabilities.mediaPlayback.commands.play.NAME, capabilities.mediaPlayback.commands.pause.NAME,
            capabilities.mediaPlayback.commands.stop.NAME }))
    device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
        { capabilities.mediaTrackControl.commands.nextTrack.NAME,
            capabilities.mediaTrackControl.commands.previousTrack.NAME }))

    -- pseudo initialisation of input source
    device:emit_event(capabilities.mediaInputSource.inputSource("wifi"))

    -- set supported input sources
    device:emit_event(capabilities.mediaInputSource.supportedInputSources(
        { "HDMI", "aux", "digital" }))
    -- {"HDMI", "USB", "aux", "bluetooth", "digital", "wifi"}))

    -- set supported keypad inputs
    device:emit_event(capabilities.keypadInput.supportedKeyCodes(
        { "UP", "DOWN", "LEFT", "RIGHT", "SELECT", "BACK", "EXIT", "MENU", "SETTINGS", "HOME", "NUMBER0", "NUMBER1",
            "NUMBER2", "NUMBER3", "NUMBER4", "NUMBER5", "NUMBER6", "NUMBER7", "NUMBER8", "NUMBER9" }))

    local device_dni = device.device_network_id

    local device_ip = device:get_field("device_ipv4")
    if not device_ip then
        device_ip = driver.registered_devices[device_dni]
    end
    log.trace(string.format("device IP: %s", device_ip))

    create_check_health_thread(driver, device)
    create_check_for_updates_thread(driver, device)

    update_connection(driver, device, device_dni, device_ip)
    refresh(driver, device)
end

local function device_added(driver, device)
    log.info("Device added: " .. device.label)
    discovery.set_device_field(driver, device)
    -- ensuring device is initialised
    device_init(driver, device)
end

local function device_changeInfo(driver, device, event, args)
    log.info("Device added: " .. device.label)
    local ip = device:get_field("device_ipv4")
    if not ip then
        log.warn("Failed to get device ip during device_changeInfo()")
        update_connection(driver, device, device.device_network_id, nil)
    else
        api.SetDeviceName(ip, device.label)
    end
end

local function do_refresh(driver, device, cmd)
    log.info("Starting do_refresh: " .. device.label)

    -- check and update device IP
    local dni = device.device_network_id
    local ip = device:get_field("device_ipv4")
    update_connection(driver, device, dni, ip)

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
        [capabilities.mediaPlayback.ID] = {
            [capabilities.mediaPlayback.commands.pause.NAME] = handlers.handle_playPause,
            [capabilities.mediaPlayback.commands.play.NAME] = handlers.handle_playPause,
            [capabilities.mediaPlayback.commands.stop.NAME] = handlers.handle_stop,
            [capabilities.mediaPlayback.commands.setPlaybackStatus.NAME] = handlers.handle_set_playback_status
        },
        [capabilities.mediaTrackControl.ID] = {
            [capabilities.mediaTrackControl.commands.nextTrack.NAME] = handlers.handle_next_track,
            [capabilities.mediaTrackControl.commands.previousTrack.NAME] = handlers.handle_previous_track
        },
        [capabilities.keypadInput.ID] = {
            [capabilities.keypadInput.commands.sendKey.NAME] = handlers.handle_send_key
        }
    },
    supported_capabilities = { capabilities.switch, capabilities.audioMute, capabilities.audioVolume,
        capabilities.mediaPlayback, capabilities.mediaTrackControl, capabilities.keypadInput
    },
    registered_devices = {}
})

----------------------------------------------------------
-- main
----------------------------------------------------------

log.info("Starting Harman Luxury run loop")
driver:run()
log.info("Exiting Harman Luxury run loop")
