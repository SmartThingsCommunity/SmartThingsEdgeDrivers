local log = require "log"
local json = require "st.json"
local RestClient = require "lunchbox.rest"
local utils = require "st.utils"
local cosock = require "cosock"
local socket = require "cosock.socket"
local ssl = require "cosock.ssl"

local jbl_api = {}
jbl_api.__index = jbl_api

local CREDENTIAL_TIME_OUT_SECONDS = 30

local SSL_CONFIG = {
    mode = "client",
    protocol = "any",
    verify = "peer",
    options = "all",
    cafile="./selfSignedRoot.crt"
}

local ADDITIONAL_HEADERS = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
}

function jbl_api.socket_builder(host, port, wrap_ssl)
    local sock, err = socket.tcp()

    if err ~= nil or (not sock) then
      return nil, (err or "unknown error creating TCP socket")
    end

    sock:setoption("keepalive", true)
    _, err = sock:connect(host, port)

    if wrap_ssl then
      sock, err =
        ssl.wrap(sock, SSL_CONFIG)
      if sock ~= nil then
        _, err = sock:dohandshake()
      elseif err ~= nil then
        log.error("Error setting up TLS: " .. err)
      end
    end

    if err ~= nil then sock = nil end

    return sock, err
end

local function get_base_url(device_ip)
    return "https://" .. device_ip .. ":4443"
end

local function process_rest_response(response, err, partial)
    if err ~= nil then
        return response, err, nil
    elseif response ~= nil then
        return json.decode(response:get_body()), nil, response.status
    else
        return nil, "no response or error received", nil
    end
  end

local function retry_fn(retry_attempts)
    local count = 0
    return function()
        count = count + 1
        return count < retry_attempts
    end
end

local function do_get(api_instance, path)
    return process_rest_response(api_instance.client:get(path, api_instance.headers, retry_fn(5)))
end

local function do_put(api_instance, path, payload)
    return process_rest_response(api_instance.client:put(path, payload, api_instance.headers, retry_fn(5)))
end

local function do_post(api_instance, path, payload)
    return process_rest_response(api_instance.client:post(path, payload, api_instance.headers, retry_fn(5)))
end



function jbl_api.new_device_manager(bridge_ip, bridge_info, socket_builder)
    local base_url = get_base_url(bridge_ip)

    return setmetatable(
        {
            headers = ADDITIONAL_HEADERS,
            client = RestClient.new(base_url, socket_builder),
            base_url = base_url,
        }, jbl_api
    )
end

function jbl_api:add_header(key, value)
    log.info("add_header : " .. key .. ", " .. value)
    self.headers[key] = value
end

function jbl_api.get_credential(bridge_ip, socket_builder)
    local start_time = cosock.socket.gettime()
    local timeout_time =  start_time + CREDENTIAL_TIME_OUT_SECONDS
    log.info("get_credential : start (" .. tostring(start_time) .. "), timeout (" .. tostring(timeout_time) .. ")")

    while true do
        local now = cosock.socket.gettime()

        local response, error, status = process_rest_response(RestClient.one_shot_get(get_base_url(bridge_ip) .. "/authcode", ADDITIONAL_HEADERS, socket_builder))
        now = cosock.socket.gettime()

        if now > timeout_time then
            log.error("get_credential take too long time : now(" .. tostring(now) .. ") > timeout (" .. tostring(timeout_time) .. ")")
            return nil
        end

        if not error and status == 200 then
            local token = response
            return token
        end

        cosock.socket.sleep(1)
    end
end

function jbl_api.get_info(device_ip, socket_builder)
    return process_rest_response(RestClient.one_shot_get(get_base_url(device_ip) .. "/info", ADDITIONAL_HEADERS, socket_builder))
end

function jbl_api:get_status()
    return do_get(self, "/status")
end

function jbl_api:get_volume()
    return do_get(self, "/volume")
end

function jbl_api:post_volume(payload)
    log.info("post volume : payload = " .. payload)
    return do_post(self, "/volume", payload)
end

function jbl_api:post_playback_uri(payload)
    log.info("post playback_uri : payload = " .. payload)
    return do_post(self, "/playbackUri", payload)
end

function jbl_api:get_playback()
    return do_get(self, "/playback")
end

function jbl_api:post_playback(payload)
    log.info("post playback : payload = " .. payload)
    return do_post(self, "/playback", payload)
end

function jbl_api:get_sse_url()
    return self.base_url .. "/events"
end

return jbl_api