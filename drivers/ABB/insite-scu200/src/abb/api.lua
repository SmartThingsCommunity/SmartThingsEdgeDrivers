local log = require("log")
local st_utils = require "st.utils"
local json = require "st.json"

-- Local imports
local config = require("config")
local utils = require("utils")
local RestClient = require "lunchbox.rest"

-- API for the ABB SCU200 Bridge
local api = {}
api.__index = api

local SSL_CONFIG = {
    mode = "client",
    protocol = "any",
    verify = "none",
    options = "all"
}

local ADDITIONAL_HEADERS = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
}

-- Method for getting the base URL
local function get_base_url(bridge_ip)
    return "https://" .. bridge_ip .. ":" .. config.REST_API_PORT
end

-- Method for processing the REST response
local function process_rest_response(response, err, partial)
    if err ~= nil then
        return response, err, nil
    elseif response ~= nil then
        local status, decoded_json = pcall(json.decode, response:get_body())

        if status and response.status == 200 then
            log.debug("process_rest_response(): Response = " .. response.status .. " " .. response:get_body())

            return decoded_json, nil, response.status
        elseif status then
            log.error("process_rest_response(): Response error = " .. response.status)

            return nil, "response status is not 200 OK", response.status
        else
            log.error("process_rest_response(): Failed to decode data")

            return nil, "failed to decode data", nil
        end
    else
        return nil, "no response or error received", nil
    end
end

-- Method for creating a retry function
local function retry_fn(retry_attempts)
    local count = 0

    return function()
        count = count + 1
        return count < retry_attempts
    end
end

-- Method for performing a GET request
local function do_get(api_instance, path)
    log.debug("do_get(): Sending GET request to " .. path)

    return process_rest_response(api_instance.client:get(path, api_instance.headers, retry_fn(5)))
end

-- Method for performing a POST request
local function do_post(api_instance, path, payload)
    log.debug("do_post(): Sending POST request to " .. path .. " with payload " .. json.encode(payload))

    return process_rest_response(api_instance.client:post(path, payload, api_instance.headers, retry_fn(5)))
end

-- Method for creating a labeled socket builder
function api.labeled_socket_builder(label)
    local socket_builder = utils.labeled_socket_builder(label, SSL_CONFIG)

    return socket_builder
end

-- Method for creating a new bridge manager
function api.new_bridge_manager(bridge_ip, bridge_dni)
    local base_url = get_base_url(bridge_ip)
    local socket_builder = api.labeled_socket_builder(bridge_dni)

    return setmetatable(
        {
            headers = st_utils.deep_copy(ADDITIONAL_HEADERS),
            client = RestClient.new(base_url, socket_builder),
            base_url = base_url
        },
        api
    )
end

-- Method for getting the thing infos
function api.get_thing_infos(bridge_ip, bridge_dni)
    local socket_builder = api.labeled_socket_builder(bridge_dni .. " (thing infos)")
    local response, error, status = process_rest_response(RestClient.one_shot_get(get_base_url(bridge_ip) .. "/devices", ADDITIONAL_HEADERS, socket_builder))

    if not error and status == 200 then
        return response
    else
        log.error("api.get_thing_infos(): Failed to get thing infos, error = " .. error)
        return nil
    end
end

-- Method for getting the bridge info
function api.get_bridge_info(bridge_ip, bridge_dni)
    local socket_builder = api.labeled_socket_builder(bridge_dni .. " (bridge info)")
    local response, error, status = process_rest_response(RestClient.one_shot_get(get_base_url(bridge_ip) .. "/bridge", ADDITIONAL_HEADERS, socket_builder))

    if not error and status == 200 then
        return response
    else
        log.error("api.get_bridge_info(): Failed to get thing infos, error = " .. error)
        return nil
    end
end

-- API methods
function api:get_devices()
    return do_get(self, "/devices")
end

function api:get_device_by_id(id)
    return do_get(self, string.format("/devices/%s", id))
end

function api:post_device_by_id(id, payload)
    return do_post(self, string.format("/devices/%s/control", id), payload)
end

function api:get_sse_url()
    return self.base_url .. "/events"
end

return api