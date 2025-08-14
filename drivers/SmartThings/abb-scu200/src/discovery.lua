local log = require "log"
local socket = require('socket')
local cosock = require "cosock"

-- Local imports
local api = require("abb.api")
local config = require("config")
local utils = require("utils")
local fields = require("fields")

-- Discovery service run within SmartThings app
local discovery = {}

local joined_bridge = {}
local joined_thing = {}

-- Method for setting the device fields
function discovery.set_device_fields(driver, device)
    local dni = utils.get_dni_from_device(device)
  
    if joined_bridge[dni] ~= nil then
        log.info("discovery.set_device_field(): Setting device field for bridge: " .. dni)
        local bridge_cache_value = driver.datastore.bridge_discovery_cache[dni]
  
        device:set_field(fields.BRIDGE_IPV4, bridge_cache_value.ip, {persist = true})
        device:set_field(fields.DEVICE_TYPE, fields.DEVICE_TYPE_BRIDGE, {persist = true})
    elseif joined_thing[dni] ~= nil then
        log.info("discovery.set_device_field(): Setting device field for thing: " .. dni)
        local thing_cache_value = driver.datastore.thing_discovery_cache[dni]
    
        device:set_field(fields.PARENT_BRIDGE_DNI, thing_cache_value.parent_bridge_dni, {persist = true})
        device:set_field(fields.THING_INFO, thing_cache_value.thing_info, {persist = true})
        device:set_field(fields.DEVICE_TYPE, fields.DEVICE_TYPE_THING, {persist = true})
    else
        log.warn("discovery.set_device_field(): Could not set device field for unknown device: " .. dni)
    end
end

-- Method for updating the bridge discovery cache
local function update_bridge_discovery_cache(driver, dni, device)
    log.info("update_bridge_discovery_cache(): Updating bridge discovery cache: " .. dni)

    driver.datastore.bridge_discovery_cache[dni] = {
        ip = device["ip"]
    }
end

-- Method for updating the thing discovery cache
local function update_thing_discovery_cache(driver, thing_dni, parent_bridge_dni, thing_info)
    log.info("update_thing_discovery_cache(): Updating thing discovery cache: " .. thing_dni)

    driver.datastore.thing_discovery_cache[thing_dni] = {
        parent_bridge_dni = parent_bridge_dni,
        thing_info = thing_info,
    }
end

-- Method for trying to add a new bridge
local function try_add_bridge(driver, dni, device)
    log.info("try_add_bridge(): Trying to add bridge: " .. dni)

    local bridge_info = api.get_bridge_info(device["ip"], dni)
    if bridge_info == nil then
        log.error("try_add_bridge(): Failed to get bridge info for bridge: " .. dni)
        return false
    end

    update_bridge_discovery_cache(driver, dni, device)

    local metadata = {
        type = config.DEVICE_TYPE,
        device_network_id = dni,
        label = bridge_info.name,
        profile = config.BRIDGE_PROFILE,
        manufacturer = config.MANUFACTURER,
        model = config.BRIDGE_TYPE,
        vendor_provided_label = config.BRIDGE_TYPE
    }

    local success, err = driver:try_create_device(metadata)

    if success then
        log.debug("try_add_bridge(): Bridge created: " .. dni)

        return true
    else
        log.error("try_add_bridge(): Failed to create bridge: " .. dni)
        log.debug("try_add_bridge(): Error: " .. err)

        return false
    end
end

-- Method for trying to add a new thing
local function try_add_thing(driver, parent_device, thing_dni, thing_info)
    local parent_device_dni = utils.get_dni_from_device(parent_device)
    log.info("try_add_thing(): Trying to add thing: " .. thing_dni .. " of type: " .. thing_info.type .. " on bridge: " .. parent_device_dni)

    update_thing_discovery_cache(driver, thing_dni, parent_device_dni, thing_info)

    if thing_info.type == utils.get_thing_exact_type(config.EDGE_CHILD_WATER_METER_TYPE) or thing_info.type == utils.get_thing_exact_type(config.EDGE_CHILD_GAS_METER_TYPE) then
        log.warn("try_add_thing(): Not supported thing type: " .. thing_info.type)
        return false
    elseif thing_info.type == utils.get_thing_exact_type(config.EDGE_CHILD_CURRENT_SENSOR_TYPE) and thing_info.properties.isExport then
        log.warn("try_add_thing(): Current sensor with production data is not supported")
        return false
    end

    local profile_ref = utils.get_thing_profile_ref(thing_info)
    if profile_ref == nil then
        log.error("try_add_thing(): Failed to get profile reference for thing: " .. thing_dni)
        return false
    end

    local parent_device_id = utils.get_device_id_from_device(parent_device)

    local metadata = {
        type = config.EDGE_CHILD_TYPE,
        label = thing_info.name,
        vendor_provided_label = thing_info.name,
        profile = profile_ref,
        manufacturer = config.MANUFACTURER,
        model = thing_info.type,
        parent_device_id = parent_device_id,
        parent_assigned_child_key = thing_info.uuid,
    }

    local success, err = driver:try_create_device(metadata)

    if success then
        log.debug("try_add_thing(): Thing created: " .. thing_dni)

        return true
    else
        log.error("try_add_thing(): Failed to create thing: " .. thing_dni)
        log.debug("try_add_thing(): Error: " .. err)

        return false
    end
end

-- SSDP Response parser
local function parse_ssdp(data)
    local res = {}

    res.status = data:sub(0, data:find('\r\n'))

    for line in data:gmatch("[^\r\n]+") do
        _, _, header, value = string.find(line, "([%w-]+):%s*([%a+-:_ /=?]*)")
        
        if header ~= nil and value ~= nil then
            res[header:lower()] = value
        end
    end

    return res
end

-- Method for finding devices
function discovery.find_devices()
    log.info("discovery.find_devices(): Finding devices")

    -- Initialize UDP socket
    local upnp = cosock.socket.udp()

    upnp:setsockname('*', 0)
    upnp:setoption("broadcast", true)
    upnp:settimeout(config.MC_TIMEOUT)

    -- Broadcast M-SEARCH request
    log.info("discovery.find_devices(): Scanning network...")

    upnp:sendto(config.MSEARCH, config.MC_ADDRESS, config.MC_PORT)

    -- Listen for responses
    local devices = {}
    local start_time = socket.gettime()

    while (socket.gettime() - start_time) < config.MC_TIMEOUT do
        local res = upnp:receivefrom()

        if res ~= nil then
            local device = parse_ssdp(res)
            local dni = string.match(device["usn"], "^uuid:([a-zA-Z0-9-]+)::" .. config.BRIDGE_URN .. "$")

            if dni ~= nil then
                local _, _, device_ip = string.find(device["location"], "https?://(%d+%.%d+%.%d+%.%d+):?%d*/?.*")
                device["ip"] = device_ip

                devices[dni] = device
            end
        end
    end

    -- Print found devices
    if next(devices) then
        for dni, device in pairs(devices) do
            log.debug("discovery.find_devices(): Device found: " .. utils.dump(device))
        end
    else
        log.debug("discovery.find_devices(): No devices found")
    end

    -- Close the UDP socket
    upnp:close()

    log.debug("discovery.find_devices(): Stop scanning network")

    if devices ~= nil then
        return devices
    end

    return nil
end

-- Start the discovery of bridges
local function discover_bridges(driver)
    log.info("discover_bridges(): Discovering bridges")

    -- Get the known devices
    local known_devices = {}

    for _, device in pairs(driver:get_devices()) do
        local dni, device_type = utils.get_dni_from_device(device)
        known_devices[dni] = device

        log.debug("discover_bridges(): Known devices: " .. dni .. " with type: " .. device_type)
    end
  
    -- Find new devices
    local found_devices = discovery.find_devices()

    if found_devices ~= nil then
        for dni, device in pairs(found_devices) do
            if not known_devices or not known_devices[dni] then
                log.info("discover_bridges(): Found new bridge: " .. dni)

                if not joined_bridge[dni] then
                    if try_add_bridge(driver, dni, device) then
                        joined_bridge[dni] = true

                        bridge_ip = device["ip"]
                    end
                else
                    log.debug("discover_bridges(): Bridge already joined: " .. dni)
                end
            else
                log.debug("discover_bridges(): Bridge already added: " .. dni)
            end
        end
    end
end

-- Start the discovery of things
local function discover_things(driver)
    log.info("discover_things(): Discovering things")

    -- Get the known devices
    local known_devices = {}

    for _, device in pairs(driver:get_devices()) do
        local dni, device_type = utils.get_dni_from_device(device)
        known_devices[dni] = device

        log.debug("discover_things(): Known devices: " .. dni .. " with type: " .. device_type)
    end

    -- Found new devices
    for bridge_dni, bridge_cache_value in pairs(driver.datastore.bridge_discovery_cache) do
        local bridge_ip = bridge_cache_value.ip
        log.info("discover_things(): Fetching things from bridge: " .. bridge_dni .. " at IP: " .. bridge_ip)

        if known_devices[bridge_dni] ~= nil and known_devices[bridge_dni]:get_field(fields.CONN_INFO) ~= nil then
            local thing_infos = api.get_thing_infos(bridge_ip, bridge_dni)
        
            if thing_infos and thing_infos.devices ~= nil then
                for _, thing_info in pairs(thing_infos.devices) do
                    if thing_info ~= nil then
                        local thing_dni = thing_info.uuid

                        log.info("discover_things(): Found thing: " .. thing_dni .. " on bridge: " .. bridge_dni)

                        if thing_dni ~= nil then
                            if not known_devices[thing_dni] then
                                if try_add_thing(driver, known_devices[bridge_dni], thing_dni, thing_info) then
                                    joined_thing[thing_dni] = true
                                end
                            elseif not joined_thing[thing_dni] then
                                log.debug("discover_things(): Thing already known: " .. thing_dni)
                            else
                                log.debug("discover_things(): Thing already joined: " .. thing_dni)
                            end
                        end
                    end

                    cosock.socket.sleep(0.2)
                end
            end
        end
    end
end

-- Main function to start the discovery service
function discovery.start(driver, _, should_continue)
    log.info("discovery.start(): Starting discovery")

    while should_continue() do
        discover_bridges(driver)
        discover_things(driver)

        cosock.socket.sleep(0.2)
    end

    log.info("discovery.start(): Ending discovery")
end

return discovery