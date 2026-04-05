local log = require('log')
local json = require('dkjson')

-- Local imports
local EventSource = require "lunchbox.sse.eventsource"
local device_manager = require("abb.device_manager")
local device_refresher = require("abb.device_refresher")
local fields = require "fields"
local utils = require "utils"

local eventsource_handler = {}

-- Method for handling an incoming SSE event
function eventsource_handler.handle_sse_event(driver, bridge, msg)
    log.debug("eventsource_handler.handle_sse_event(): Handling SSE event (TYPE: " .. msg.type .. ", DATA: " .. msg.data .. ")")

    if msg.type == "valueChanged" then
        local data = json.decode(msg.data)

        if data ~= nil and next(data) ~= nil then
            -- Find the device
            local device = nil

            local child_devices = bridge:get_child_list()
            for _, thing_device in ipairs(child_devices) do
                local dni = utils.get_dni_from_device(thing_device)

                if dni == data.uuid then
                    device = thing_device
                    break
                end
            end

            if device == nil then
                log.warn("eventsource_handler.handle_sse_event(): Failed to find the device with dni: " .. data.uuid)
                return
            end

            -- Prepare the values
            local values = {}

            values[data.attribute.name] = data.attribute.value

            -- Refresh the device
            if device_refresher.refresh_device(driver, device, values) then
                -- Define online status
                device:online()
            else
                log.error("eventsource_handler.handle_sse_event(): Failed to update the device's values")

                -- Set device as offline
                device:offline()
            end
        else
            log.error("eventsource_handler.handle_sse_event(): Failed to decode JSON data: " .. msg.data)
        end
    elseif msg.type == "noDevices" then
        log.info("eventsource_handler.handle_sse_event(): No devices to monitor found")

        eventsource_handler.close_sse(driver, bridge)
    elseif msg.type == "refreshConnection" then
        log.info("eventsource_handler.handle_sse_event(): Refreshing connection")

        eventsource_handler.close_sse(driver, bridge)
        eventsource_handler.create_sse(driver, bridge)
    else
        log.warn("eventsource_handler.handle_sse_event(): Unknown SSE event type: " .. msg.type)
    end
end

-- Method for creating SSE
function eventsource_handler.create_sse(driver, device)
    local dni = utils.get_dni_from_device(device)
    log.info("eventsource_handler.create_sse(): Creating SSE for dni: " .. dni)

    local conn_info = device:get_field(fields.CONN_INFO)

    if not device_manager.is_valid_connection(driver, device, conn_info) then
        log.error("eventsource_handler.create_sse(): Invalid connection for dni: " .. dni)
        return
    end

    local sse_url = conn_info:get_sse_url()
    if not sse_url then
        log.error("eventsource_handler.create_sse(): Failed to get sse_url for dni: " .. dni)
        return
    end

    log.trace("eventsource_handler.create_sse(): Creating SSE EventSource for " .. dni .. " with sse_url: " .. sse_url)
    local eventsource = EventSource.new(sse_url, {}, nil, nil)

    eventsource.onmessage = function(msg)
        if msg then
            eventsource_handler.handle_sse_event(driver, device, msg)
        end
    end

    eventsource.onerror = function()
        log.error("eventsource_handler.create_sse(): Error in the eventsource for dni: " .. dni)
        device:offline()
    end

    eventsource.onopen = function(msg)
        log.info("eventsource_handler.create_sse(): Eventsource has been opened for dni: " .. dni)
        device:online()
    end

    local old_eventsource = device:get_field(fields.EVENT_SOURCE)
    if old_eventsource then
        log.info("eventsource_handler.create_sse(): Eventsource has been closed for dni: " .. dni)
        old_eventsource:close()
    end
    device:set_field(fields.EVENT_SOURCE, eventsource)
end

-- Method for closing SSE
function eventsource_handler.close_sse(driver, device)
    local dni = utils.get_dni_from_device(device)
    log.info("eventsource_handler.close_sse(): Closing SSE for dni: " .. dni)

    local eventsource = device:get_field(fields.EVENT_SOURCE)
    if eventsource then
        log.info("eventsource_handler.close_sse(): Closing eventsource for device: " .. dni)
        eventsource:close()
    end
end

return eventsource_handler
