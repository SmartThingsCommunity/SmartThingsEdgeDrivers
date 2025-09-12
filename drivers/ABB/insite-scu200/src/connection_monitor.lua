local log = require("log")

-- Local imports
local fields = require("fields")
local utils = require("utils")
local discovery = require("discovery")
local eventsource_handler = require("eventsource_handler")
local device_manager = require("abb.device_manager")

-- Connection monitor for the SCU200 Bridge
local connection_monitor = {}

function connection_monitor.update_connection(driver, device, bridge_ip)
    local bridge_dni = utils.get_dni_from_device(device)
    log.info("connection_monitor.update_connection(): Update connection for bridge device: " .. bridge_dni)

    local conn_info = device_manager.get_bridge_connection_info(driver, bridge_dni, bridge_ip)

    if device_manager.is_valid_connection(driver, device, conn_info) then
        device:set_field(fields.CONN_INFO, conn_info)
        eventsource_handler.create_sse(driver, device)
    end
end

local function find_new_connection(driver, device)
    local dni = utils.get_dni_from_device(device)
    log.info("find_new_connection(): Find new connection for dni = " .. dni)

    local found_devices = discovery.find_devices()

    if found_devices ~= nil then
        local found_device = found_devices[dni]

        if found_device then
            log.info("find_new_connection(): Found new connection for dni = " .. dni)

            local ip = found_device.ip

            device:set_field(fields.BRIDGE_IPV4, ip, {persist = true})
            connection_monitor.update_connection(driver, device, ip)
        end
    end
end

function connection_monitor.check_and_update_connection(driver, device)
    local dni = utils.get_dni_from_device(device)
    local conn_info = device:get_field(fields.CONN_INFO)

    if not device_manager.is_valid_connection(driver, device, conn_info) then
        log.error("connection_monitor.check_and_update_connection(): Disconnected from device. Try to find new connection for dni = " .. dni)

        find_new_connection(driver, device)
    end
end

-- Method for monitoring the connection of the bridge devices
function connection_monitor.monitor_connections(driver)
    local device_list = driver:get_devices()

    for _, device in ipairs(device_list) do
        if device:get_field(fields.DEVICE_TYPE) == fields.DEVICE_TYPE_BRIDGE then
            local dni = utils.get_dni_from_device(device)
            log.info("connection_monitor.monitor_connections(): Monitoring connection for bridge device: " .. dni)

            connection_monitor.check_and_update_connection(driver, device)
            device_manager.bridge_monitor(driver, device)
        end
    end
end

return connection_monitor