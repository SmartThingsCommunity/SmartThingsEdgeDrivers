local log = require "log"
local json = require "st.json"
local RestClient = require "lunchbox.rest"
local utils = require "utils"
local cosock = require "cosock"

local jbl_api = {}
jbl_api.__index = jbl_api

local CREDENTIAL_TIME_OUT_SECONDS = 30

local SSL_CONFIG = {
  mode = "client",
  protocol = "any",
  verify = "peer",
  options = "all",
  cafile = "./selfSignedRoot.crt"
}

local ADDITIONAL_HEADERS = {
  ["Accept"] = "application/json",
  ["Content-Type"] = "application/json",
}

function jbl_api.labeled_socket_builder(label)
  local socket_builder = utils.labeled_socket_builder(label, SSL_CONFIG)
  return socket_builder
end

local function get_base_url(device_ip)
  return "https://" .. device_ip .. ":4443"
end

local function process_rest_response(response, err, partial)
  if err ~= nil then
    return response, err, nil
  elseif response ~= nil then
    local status, decoded_json = pcall(json.decode, response:get_body())
    if status then
      return decoded_json, nil, response.status
    else
      log.error(string.format("process_rest_response : failed to decode data"))
      return nil, "failed to decode data", nil
    end
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
  local timeout_time = start_time + CREDENTIAL_TIME_OUT_SECONDS
  log.info("get_credential : start (" .. tostring(start_time) .. "), timeout (" .. tostring(timeout_time) .. ")")

  while true do
    local response, error, status = process_rest_response(RestClient.one_shot_get(get_base_url(bridge_ip) .. "/authcode", ADDITIONAL_HEADERS, socket_builder))
    local now = cosock.socket.gettime()

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
  local raw_device_info = process_rest_response(RestClient.one_shot_get(get_base_url(device_ip) .. "/info", ADDITIONAL_HEADERS, socket_builder))
  if raw_device_info == nil then
    log.error("failed to get device info")
    return nil
  end

  local device_info = {
    deviceType = raw_device_info.deviceType or "",
    firmwareVersion = raw_device_info.firmwareVersion or "",
    label = raw_device_info.label or "",
    manufacturerName = raw_device_info.manufacturerName or "",
    modelName = raw_device_info.modelName or "",
    serialNumber = raw_device_info.serialNumber or "",
  }

  return device_info
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
