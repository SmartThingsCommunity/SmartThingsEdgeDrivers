local caps = require('st.capabilities')
local log = require('log')
local json = require('dkjson')

-- Local imports
local utils = require('utils')
local fields = require('fields')
local config = require("config")
local device_manager = require('abb.device_manager')
local connection_monitor = require('connection_monitor')

-- Commands handler for the bridge and thing devices
local commands = {}

-- Method for posting the payload to the device
local function post_payload(device, payload)
    local dni = utils.get_dni_from_device(device)
    local communication_device = device:get_parent_device() or device
    local conn_info = communication_device:get_field(fields.CONN_INFO)

    local _, err, status = conn_info:post_device_by_id(dni, payload)
    if not err and status == 200 then
        log.info("post_payload(): Success, dni = " .. dni)

        return true
    else
        status = status or "nil"
        log.error("post_payload(): Error, err = " .. err .. ", status = " .. status .. ", dni = " .. dni)

        device:offline()

        return false
    end
end

-- Switch on command
function commands.switch_on(driver, device, cmd)
    local dni, _ = utils.get_dni_from_device(device)
    log.info("commands.switch_on(): Switching on capablity within dni = " .. dni)

    local device_model = utils.get_device_model(device)

    local payload = nil
    local event = nil
    if device_model == utils.get_thing_exact_type(config.EDGE_CHILD_OUTPUT_MODULE_TYPE) then
        payload = json.encode({capability = cmd.capability, command = cmd.command})
        event = caps.switch.switch.on()
    end

    if payload ~= nil and event ~= nil then
        local bridge = device:get_parent_device()

        bridge.thread:call_with_delay(0, function()  -- Run within bridge thread to use the same connection
            local success = post_payload(device, payload)
            if success then
                device:emit_event(event)
            end
        end)
    end
end

-- Switch off commands
function commands.switch_off(driver, device, cmd)
    local dni, _ = utils.get_dni_from_device(device)
    log.info("commands.switch_off(): Switching off capablity within dni = " .. dni)

    local device_model = utils.get_device_model(device)

    local payload = nil
    local event = nil
    if device_model == utils.get_thing_exact_type(config.EDGE_CHILD_OUTPUT_MODULE_TYPE) then
        payload = json.encode({capability = cmd.capability, command = cmd.command})
        event = caps.switch.switch.off()
    end

    if payload ~= nil and event ~= nil then
        local bridge = device:get_parent_device()

        bridge.thread:call_with_delay(0, function()  -- Run within bridge thread to use the same connection
            local success = post_payload(device, payload)
            if success then
                device:emit_event(event)
            end
        end)
    end
end

-- Refresh command
function commands.refresh(driver, device, cmd)
    local dni, device_type = utils.get_dni_from_device(device)
    log.info("commands.refresh(): Refresh capability within dni = " .. dni)

    if device_type == fields.DEVICE_TYPE_BRIDGE then
        connection_monitor.check_and_update_connection(driver, device)
        local child_devices = device:get_child_list()

        for _, thing_device in ipairs(child_devices) do
            device_manager.refresh(driver, thing_device)
        end
    elseif device_type == fields.DEVICE_TYPE_THING then
        local bridge = device:get_parent_device()

        if bridge.thread ~= nil then
            bridge.thread:call_with_delay(0, function()  -- Run within bridge thread to use the same connection
                device_manager.refresh(driver, device)
            end)
        end
    end
end

return commands