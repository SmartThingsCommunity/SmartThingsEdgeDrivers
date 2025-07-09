local log = require('log')

-- Local imports
local fields = require('fields')
local utils = require('utils')
local discovery = require('discovery')
local commands = require('commands')
local connection_monitor = require('connection_monitor')
local device_manager = require('abb.device_manager')
local eventsource_handler = require("eventsource_handler")

-- Lifecycles handlers for the driver
local lifecycles = {}

-- Lifecycle handler for a device which has been initialized
function lifecycles.init(driver, device)
    local dni, device_type = utils.get_dni_from_device(device)

    -- Verify if the device has already been initialized
    if device:get_field(fields._INIT) then
        log.info("lifecycles.init(): Device already initialized: " .. dni .. " of type: " .. device_type)
        return
    end

    log.info("lifecycles.init(): Initializing device: " .. dni .. " of type: " .. device_type)

    if device_type == fields.DEVICE_TYPE_BRIDGE then
        if driver.datastore.bridge_discovery_cache[dni] then
            log.debug("lifecycles.init(): Setting unsaved bridge fields")
            discovery.set_device_fields(driver, device)
        end

        local bridge_ip = device:get_field(fields.BRIDGE_IPV4)

        connection_monitor.update_connection(driver, device, bridge_ip)
    elseif device_type == fields.DEVICE_TYPE_THING then
        if driver.datastore.thing_discovery_cache[dni] then
            log.debug("lifecycles.init(): Setting unsaved thing fields")
            discovery.set_device_fields(driver, device)
        end

        -- Refresh the device manually
        commands.refresh(driver, device, _)
        
        -- Refresh schedule
        local refresh_period = utils.get_thing_refresh_period(device)

        device.thread:call_on_schedule(
            refresh_period,
            function ()
                return commands.refresh(driver, device, _)
            end,
            "Refresh schedule")
    end

    -- Set the device as initialized
    device:set_field(fields._INIT, true, {persist = false})
end

-- Lifecycle handler for a device which has been added
function lifecycles.added(driver, device)
    local dni, device_type = utils.get_dni_from_device(device)
    log.info("lifecycles.added(): Adding device: " .. dni .. " of type: " .. device_type)

    -- Force the initialization due to cases where the device is not initialized after being added
    lifecycles.init(driver, device)
end

-- Lifecycle handler for a device which has been removed
function lifecycles.removed(driver, device)
    local dni, device_type = utils.get_dni_from_device(device)
    log.info("lifecycles.removed(): Removing device: " .. dni .. " of type: " .. device_type)

    if device_type == fields.DEVICE_TYPE_BRIDGE then
        log.debug("lifecycles.removed(): Closing SSE for device: " .. dni)

        eventsource_handler.close_sse(driver, device)
    elseif device_type == fields.DEVICE_TYPE_THING then
        log.debug("lifecycles.removed(): Removing schedules for device: " .. dni)

        -- Remove the schedules to avoid unnecessary CPU processing
        for timer in pairs(device.thread.timers) do
            device.thread:cancel_timer(timer)
        end
    end
end

return lifecycles