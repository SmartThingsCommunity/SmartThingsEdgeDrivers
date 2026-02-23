local log = require("log")
local socket = require "cosock.socket"
local ssl = require "cosock.ssl"

-- Local imports
local config = require("config")
local fields = require("fields")

-- Utility functions for the SmartThings edge driver
local utils = {}

-- Get the device id from the device
function utils.get_dni_from_device(device)
    if device.parent_assigned_child_key then
        local thing_dni = device.parent_assigned_child_key

        return thing_dni, fields.DEVICE_TYPE_THING
    else
        local bridge_dni = device.device_network_id

        return bridge_dni, fields.DEVICE_TYPE_BRIDGE
    end
end

-- Get the device ID
function utils.get_device_id_from_device(device)
    return device.st_store.id
end

-- Get the device model
function utils.get_device_model(device)
    local thing_info = device:get_field(fields.THING_INFO)

    if thing_info == nil then
        return nil
    end

    return thing_info.type
end

-- Get the device IP address
function utils.get_device_ip_address(device)
    local _, device_type = utils.get_dni_from_device(device)

    if device_type == fields.DEVICE_TYPE_BRIDGE then
        return device:get_field(fields.BRIDGE_IPV4)
    else
        local bridge = device:get_parent_device()

        return bridge:get_field(fields.BRIDGE_IPV4)
    end
end

-- Method for getting edge child device version by type
function utils.get_edge_child_device_version(edge_child_device_type)
    local edge_child_device_versions = {
        [config.EDGE_CHILD_CURRENT_SENSOR_TYPE]      = config.EDGE_CHILD_CURRENT_SENSOR_VERSION,
        [config.EDGE_CHILD_ENERGY_METER_MODULE_TYPE] = config.EDGE_CHILD_ENERGY_METER_MODULE_VERSION,
        [config.EDGE_CHILD_AUXILIARY_CONTACT_TYPE]   = config.EDGE_CHILD_AUXILIARY_CONTACT_VERSION,
        [config.EDGE_CHILD_OUTPUT_MODULE_TYPE]       = config.EDGE_CHILD_OUTPUT_MODULE_VERSION,
        [config.EDGE_CHILD_ENERGY_METER_TYPE]        = config.EDGE_CHILD_ENERGY_METER_VERSION,
        [config.EDGE_CHILD_WATER_METER_TYPE]         = config.EDGE_CHILD_WATER_METER_VERSION,
        [config.EDGE_CHILD_GAS_METER_TYPE]           = config.EDGE_CHILD_GAS_METER_VERSION,
        [config.EDGE_CHILD_USB_ENERGY_METER_TYPE]    = config.EDGE_CHILD_USB_ENERGY_METER_VERSION
    }

    return edge_child_device_versions[edge_child_device_type]
end

-- Method for getting the thing exact type
function utils.get_thing_exact_type(edge_child_device_type)
    local device_version = utils.get_edge_child_device_version(edge_child_device_type)

    if device_version == nil then
        return nil
    end

    return config.MANUFACTURER .. "_" .. config.BRIDGE_TYPE .. "_" .. edge_child_device_type .. "_" .. device_version
end

-- Method for getting the thing profile reference
function utils.get_thing_profile_ref(thing_info)
    if thing_info.type == utils.get_thing_exact_type(config.EDGE_CHILD_CURRENT_SENSOR_TYPE) then
        if thing_info.properties.isExport then
            return config.EDGE_CHILD_CURRENT_SENSOR_PRODUCTION_PROFILE
        else
            return config.EDGE_CHILD_CURRENT_SENSOR_CONSUMPTION_PROFILE
        end
    end

    local thing_profiles = {
        [utils.get_thing_exact_type(config.EDGE_CHILD_ENERGY_METER_MODULE_TYPE)] = config.EDGE_CHILD_ENERGY_METER_PROFILE,
        [utils.get_thing_exact_type(config.EDGE_CHILD_AUXILIARY_CONTACT_TYPE)]   = config.EDGE_CHILD_AUXILIARY_CONTACT_PROFILE,
        [utils.get_thing_exact_type(config.EDGE_CHILD_OUTPUT_MODULE_TYPE)]       = config.EDGE_CHILD_OUTPUT_MODULE_PROFILE,
        [utils.get_thing_exact_type(config.EDGE_CHILD_ENERGY_METER_TYPE)]        = config.EDGE_CHILD_ENERGY_METER_PROFILE,
        [utils.get_thing_exact_type(config.EDGE_CHILD_WATER_METER_TYPE)]         = config.EDGE_CHILD_WATER_METER_PROFILE,
        [utils.get_thing_exact_type(config.EDGE_CHILD_GAS_METER_TYPE)]           = config.EDGE_CHILD_GAS_METER_PROFILE,
        [utils.get_thing_exact_type(config.EDGE_CHILD_USB_ENERGY_METER_TYPE)]    = config.EDGE_CHILD_USB_ENERGY_METER_PROFILE
    }

    return thing_profiles[thing_info.type]
end

-- Method for getting the thing refresh period
function utils.get_thing_refresh_period(device)
    local device_model = utils.get_device_model(device)

    local thing_refresh_periods = {
        [utils.get_thing_exact_type(config.EDGE_CHILD_CURRENT_SENSOR_TYPE)]      = config.EDGE_CHILD_CURRENT_SENSOR_REFRESH_PERIOD,
        [utils.get_thing_exact_type(config.EDGE_CHILD_ENERGY_METER_MODULE_TYPE)] = config.EDGE_CHILD_ENERGY_METER_MODULE_REFRESH_PERIOD,
        [utils.get_thing_exact_type(config.EDGE_CHILD_AUXILIARY_CONTACT_TYPE)]   = config.EDGE_CHILD_AUXILIARY_CONTACT_REFRESH_PERIOD,
        [utils.get_thing_exact_type(config.EDGE_CHILD_OUTPUT_MODULE_TYPE)]       = config.EDGE_CHILD_OUTPUT_MODULE_REFRESH_PERIOD,
        [utils.get_thing_exact_type(config.EDGE_CHILD_ENERGY_METER_TYPE)]        = config.EDGE_CHILD_ENERGY_METER_REFRESH_PERIOD,
        [utils.get_thing_exact_type(config.EDGE_CHILD_WATER_METER_TYPE)]         = config.EDGE_CHILD_WATER_METER_REFRESH_PERIOD,
        [utils.get_thing_exact_type(config.EDGE_CHILD_GAS_METER_TYPE)]           = config.EDGE_CHILD_GAS_METER_REFRESH_PERIOD,
        [utils.get_thing_exact_type(config.EDGE_CHILD_USB_ENERGY_METER_TYPE)]    = config.EDGE_CHILD_USB_ENERGY_METER_REFRESH_PERIOD
    }

    return thing_refresh_periods[device_model]
end

-- Method for dumping a table to string
function utils.dump(o)
    if type(o) == "table" then
        local s = '{'

        for k,v in pairs(o) do
            if type(k) ~= "number" then k = '"'..k..'"' end
            s = s .. ' ['..k..'] = ' .. utils.dump(v) .. ','
        end

        return s .. '} '
    else
        return tostring(o)
    end
end

-- Method for building a exponential backoff time value generator
function utils.backoff_builder(max, inc, rand)
    local count = 0
    inc = inc or 1

    return function()
        local randval = 0
        if rand then
            randval = math.random() * rand * 2 - rand
        end

        local base = inc * (2 ^ count - 1)
        count = count + 1

        -- ensure base backoff (not including random factor) is less than max
        if max then base = math.min(base, max) end

        -- ensure total backoff is >= 0
        return math.max(base + randval, 0)
    end
end

-- Method for creating a labeled socket
function utils.labeled_socket_builder(label, ssl_config)
    label = (label or "")
    if #label > 0 then
        label = label .. " "
    end

    if not ssl_config then
        ssl_config = { mode = "client", protocol = "any", verify = "none", options = "all" }
    end

    local function make_socket(host, port, wrap_ssl)
        log.info("utils.labeled_socket_builder(): Creating TCP socket for REST Connection: " .. label)
        local _ = nil
        local sock, err = socket.tcp()

        if err ~= nil or (not sock) then
            return nil, (err or "unknown error creating TCP socket")
        end

        log.debug("utils.labeled_socket_builder(): Setting TCP socket timeout for REST Connection: " .. label)
        _, err = sock:settimeout(60)
        if err ~= nil then
            return nil, "settimeout error: " .. err
        end

        log.debug("utils.labeled_socket_builder(): Connecting TCP socket for REST Connection: " .. label)
        _, err = sock:connect(host, port)
        if err ~= nil then
            return nil, "Connect error: " .. err
        end

        log.debug("utils.labeled_socket_builder(): Set Keepalive for TCP socket for REST Connection: " .. label)
        _, err = sock:setoption("keepalive", true)
        if err ~= nil then
            return nil, "Setoption error: " .. err
        end

        if wrap_ssl then
            log.debug("utils.labeled_socket_builder(): Creating SSL wrapper for REST Connection: " .. label)
            sock, err = ssl.wrap(sock, ssl_config)
            if err ~= nil then
                return nil, "SSL wrap error: " .. err
            end

            log.debug("utils.labeled_socket_builder(): Performing SSL handshake for REST Connection: " .. label)
            _, err = sock:dohandshake()
            if err ~= nil then
                return nil, "Error with SSL handshake: " .. err
            end
        end

        log.info("utils.labeled_socket_builder(): Successfully created TCP connection: " .. label)
        return sock, err
    end

    return make_socket
end

return utils