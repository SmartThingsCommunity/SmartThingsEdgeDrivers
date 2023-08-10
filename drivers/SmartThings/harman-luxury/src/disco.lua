local mdns = require "st.mdns"
local socket = require "cosock.socket"
local log = require "log"

local disco_helper = require "disco_helper"
local devices = require "devices"

local SERVICE_TYPE = "_sue-st._tcp"
local DOMAIN = "local"

local Discovery = {}

local function update_device_discovery_cache(driver, dni, params)
    log.info("update_device_discovery_cache for device dni: " .. tostring(dni) .. ", " .. tostring(params.ip))
    local device_info = devices.get_device_info(dni, params)
    driver.registered_devices[dni] = {
        ip = params.ip,
        device_info = device_info
    }
end

local function try_add_device(driver, device_dni, device_params)
    log.trace("try_add_device : dni=" .. tostring(device_dni) .. ", ip=" .. tostring(device_params.ip))

    update_device_discovery_cache(driver, device_dni, device_params)

    local device_info = devices.get_device_info(device_dni, device_params)

    if not device_info then
        log.error("failed to create device create msg. device_info is nil. dni = " .. device_dni)
        return nil
    end

    driver:try_create_device(device_info)
end

function Discovery.set_device_field(driver, device)
    log.info("set_device_field : dni = " .. tostring(device.device_network_id))
    local device_cache_value = driver.registered_devices[device.device_network_id]

    -- persistent fields
    device:set_field("device_ipv4", device_cache_value.ip, {
        persist = true
    })
    device:set_field("device_info", device_cache_value.device_info, {
        persist = true
    })
end

local function find_params_table(driver)
    log.info("Discovery.find_params_table")

    local discovery_responses = mdns.discover(SERVICE_TYPE, DOMAIN) or {
        answers = {},
        additional = {}
    }

    local dni_params_table = disco_helper.get_dni_ip_table_from_mdns_responses(driver, SERVICE_TYPE, DOMAIN,
        discovery_responses)

    return dni_params_table
end

local function discovery_device(driver)
    local unknown_discovered_devices = {}
    local known_discovered_devices = {}
    local known_devices = {}

    log.debug("\n\n--- Initialising known devices list ---\n")
    for _, device in pairs(driver:get_devices()) do
        known_devices[device.device_network_id] = device
    end

    log.debug("\n\n--- Creating the parameters table ---\n")
    local params_table = find_params_table(driver)

    log.debug("\n\n--- Checking if devices are known or not ---\n")
    for dni, params in pairs(params_table) do
        log.info("discovery_device dni = " .. tostring(dni) .. ", ip = " .. tostring(params.ip))
        if not known_devices or not known_devices[dni] then
            unknown_discovered_devices[dni] = params
        else
            known_discovered_devices[dni] = params
        end
    end

    log.debug("\n\n--- Update devices cache ---\n")
    for dni, params in pairs(known_discovered_devices) do
        log.trace("known dni=" .. tostring(dni) .. ", ip=" .. tostring(params.ip))
        if driver.registered_devices[dni] then
            update_device_discovery_cache(driver, dni, params)
            Discovery.set_device_field(driver, known_devices[dni])
        end
    end

    if unknown_discovered_devices then
        log.debug("\n\n--- Try to create unkown devices ---\n")
        for dni, ip in pairs(unknown_discovered_devices) do
            log.trace("unknown dni=" .. tostring(dni) .. ", ip=" .. tostring(ip))
            if not driver.registered_devices[dni] then
                try_add_device(driver, dni, params_table[dni])
            end
        end
    end
end

function Discovery.find_ip_table(driver)
    log.info("Discovery.find_ip_table")

    local dni_params_table = find_params_table(driver)

    local dni_ip_table = {}
    for dni, params in pairs(dni_params_table) do
        dni_ip_table[dni] = params.ip
    end

    return dni_ip_table
end

function Discovery.discovery_handler(driver, _, should_continue)
    log.info("Starting Harman Luxury discovery")

    while should_continue() do
        discovery_device(driver)
        socket.sleep(0.5)
    end
    log.info("Ending Harman Luxury discovery")
end

return Discovery
