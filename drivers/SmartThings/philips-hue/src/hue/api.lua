local cosock = require "cosock"
local channel = require "cosock.channel"

local json = require "st.json"
local log = require "log"
local RestClient = require "lunchbox.rest"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local HueDeviceTypes = require "hue_device_types"

-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local APPLICATION_KEY_HEADER = "hue-application-key"

---@class HueResourceResponse<T>: { errors: table[], data: T[] }

---@class HueApiKeyResponse: { error: { description: string }?, success: { username: string, client_key: string|nil }? }

---@enum ControlMessageTypes
local ControlMessageTypes = {
  Shutdown = "shutdown",
  Get = "get",
  Put = "put",
  Update = "update",
}

local ControlMessageBuilders = {
  Shutdown = function() return { _type = ControlMessageTypes.Shutdown } end,
  Get = function(path, reply_tx) return { _type = ControlMessageTypes.Get, path = path, reply_tx = reply_tx } end,
  Put = function(path, payload, reply_tx)
    return { _type = ControlMessageTypes.Put, path = path, payload = payload, reply_tx = reply_tx }
  end,
  Update = function(base_url, api_key)
    return { _type = ControlMessageTypes.Update, base_url = base_url, api_key = api_key, }
  end
}

local function try_send(instance, message)
  if not instance._ctrl_tx then
    log.error(st_utils.stringify_table(message, "Couldn't send the followings due to closed transmit channel", false))
  end

  local success, err = pcall(instance._ctrl_tx.send, instance._ctrl_tx, message)
  if not success then
    log.error(string.format("Failed to transmit Hue Control Message: %s", err))
  end
end

local function do_shutdown(instance)
  if instance._running then
    try_send(instance, ControlMessageBuilders.Shutdown())
    instance._running = false
  end
end

--- Phillips Hue REST API Module
--- @class PhilipsHueApi
--- @field public headers table<string,string>
--- @field package client RestClient
--- @field package _ctrl_tx table
--- @field package _running boolean
local PhilipsHueApi = {}
PhilipsHueApi.__index = PhilipsHueApi

PhilipsHueApi.MIN_CLIP_V2_SWVERSION = 1948086000
PhilipsHueApi.APPLICATION_KEY_HEADER = APPLICATION_KEY_HEADER

local function retry_fn(retry_attempts)
  local count = 0
  return function()
    count = count + 1
    return count < retry_attempts
  end
end

---@param response Response?
---@param err string?
---@param partial string?
---@param err_callback fun(err: string)?
---@return table? tbl the table representation of the JSON response, nil on error
---@return string? err the error message, nil on success
---@return string? partial the partial response if the response was not complete
---@return ...
local function process_rest_response(response, err, partial, err_callback)
  if err == nil and response == nil then
    log.error_with({ hub_logs = true },
      st_utils.stringify_table(
        {
          resp = response,
          maybe_err = err,
          maybe_partial = partial
        },
        "[PhilipsHueApi] Unexpected nil for both response and error processing REST reply",
        false
      )
    )
  end
  if err ~= nil then
    if type(err_callback) == "function" then err_callback(err) end
    return response, err, partial
  elseif response ~= nil then
    local body, err = response:get_body()
    if not body then
      return nil, err
    end
    local json_result = table.pack(pcall(json.decode, body))
    local success = table.remove(json_result, 1)

    if not success then
      return nil, st_utils.stringify_table(
        { response_body = body, json = json_result }, "Couldn't decode JSON in SSE callback", false
      )
    end

    return table.unpack(json_result, 1, json_result.n)
  else
    return nil, "no response or error received"
  end
end

function PhilipsHueApi.new_bridge_manager(base_url, api_key, socket_builder)
  log.debug(st_utils.stringify_table(
    { base_url, api_key },
    "Creating new Bridge Manager:",
    true
  ))
  local control_tx, control_rx = channel.new()
  control_rx:settimeout(30)
  local self = setmetatable(
    {
      headers = { [APPLICATION_KEY_HEADER] = api_key or "" },
      client = RestClient.new(base_url, socket_builder),
      _ctrl_tx = control_tx,
      _running = true
    }, PhilipsHueApi
  )

  cosock.spawn(function()
    local rest_err_callback = function(_err) self.client:close_socket() end
    while self._running == true do
      local msg, err = control_rx:receive()
      if err then
        if err ~= "timeout" then
          log.error_with({ hub_logs = true }, "[PhilipsHueApi] Error receiving on control channel for REST API thread",
            err)
        else
          log.info_with({ hub_logs = true }, "Timeout on Hue API Control Channel, continuing")
        end
        goto continue
      end

      if msg and msg._type then
        if msg._type == ControlMessageTypes.Shutdown then
          log.info_with({ hub_logs = true }, "[PhilipsHueApi] REST API Control Thread received shutdown message");
          self._running = false
          goto continue
        end

        if msg._type == ControlMessageTypes.Update then
          self.client:update_base_url(msg.base_url)
          self.headers[APPLICATION_KEY_HEADER] = msg.api_key
          goto continue
        end

        local path, reply_tx = msg.path, msg.reply_tx
        if msg._type == ControlMessageTypes.Get then
          local get_resp, get_err, partial = self.client:get(path, self.headers, retry_fn(5))
          reply_tx:send(
            table.pack(process_rest_response(get_resp, get_err, partial, rest_err_callback))
          )
        elseif msg._type == ControlMessageTypes.Put then
          local payload = msg.payload
          local put_resp, put_err, partial = self.client:put(path, payload, self.headers, retry_fn(5))
          reply_tx:send(
            table.pack(process_rest_response(put_resp, put_err, partial, rest_err_callback))
          )
        end
      else
        log.warn(
          st_utils.stringify_table(msg, "[PhilipsHueApi] Unexpected Message on REST API Control Channel", false))
      end

      ::continue::
    end
    if self._ctrl_tx then
      self._ctrl_tx = nil
    end
    if self.client then
      self.client:shutdown()
      self.client = nil
    end
  end, string.format("Hue API Thread for %s", base_url))

  return self
end

function PhilipsHueApi:shutdown()
  do_shutdown(self)
end

function PhilipsHueApi:update_connection(hub_base_url, api_key)
  local msg = ControlMessageBuilders.Update(hub_base_url, api_key)
  try_send(self, msg)
end

---@param instance PhilipsHueApi
---@param path string
---@return table|nil response REST response, nil if error
---@return nil|string error nil on success
---@return ...
local function do_get(instance, path)
  local reply_tx, reply_rx = channel.new()
  reply_rx:settimeout(10)
  local msg = ControlMessageBuilders.Get(path, reply_tx);
  try_send(instance, msg)
  local recv, err = reply_rx:receive()
  if err ~= nil then
    instance.client:close_socket()
    return nil, "cosock error: " .. err
  end
  return table.unpack(recv, 1, recv.n)
end

---@param instance PhilipsHueApi
---@param path string
---@param payload string
---@return table|nil response REST response, nil if error
---@return nil|string error nil on success
---@return ...
local function do_put(instance, path, payload)
  local reply_tx, reply_rx = channel.new()
  reply_rx:settimeout(10)
  local msg = ControlMessageBuilders.Put(path, payload, reply_tx);
  try_send(instance, msg)
  local recv, err = reply_rx:receive()
  if err ~= nil then
    instance.client:close_socket()
    return nil, "cosock error: " .. err
  end
  return table.unpack(recv, 1, recv.n)
end

---@param bridge_ip string
---@param socket_builder nil|function optional an override to the default socket factory callback
---@return HueBridgeInfo|nil bridge_info nil on err
---@return nil|string error nil on success
---@return nil|string partial partial response if available, nil otherwise
---@return ...
function PhilipsHueApi.get_bridge_info(bridge_ip, socket_builder)
  local tx, rx = channel.new()
  rx:settimeout(10)
  cosock.spawn(
    function()
      tx:send(table.pack(process_rest_response(RestClient.one_shot_get("https://" .. bridge_ip .. "/api/config", nil,
        socket_builder))))
    end,
    string.format("%s get_bridge_info", bridge_ip)
  )
  local recv, err = rx:receive()
  if err ~= nil then
    return nil, "cosock error: " .. err
  end
  return table.unpack(recv, 1, recv.n)
end

---@param bridge_ip string
---@param socket_builder nil|function optional an override to the default socket factory callback
---@return HueApiKeyResponse[]? api_key_response nil on err
---@return string? error nil on success
---@return string? partial partial response if available, nil otherwise
---@return ...
function PhilipsHueApi.request_api_key(bridge_ip, socket_builder)
  local tx, rx = channel.new()
  rx:settimeout(10)
  cosock.spawn(
    function()
      local body = json.encode { devicetype = "smartthings_edge_driver#" .. bridge_ip, generateclientkey = true }
      tx:send(table.pack(process_rest_response(RestClient.one_shot_post("https://" .. bridge_ip .. "/api", body, nil,
        socket_builder))))
    end,
    string.format("%s request_api_key", bridge_ip)
  )
  local recv, err = rx:receive()
  if err ~= nil then
    return nil, "cosock error: " .. err
  end
  return table.unpack(recv, 1, recv.n)
end

---@param rtype string
---@return HueResourceResponse<HueResourceInfo>|nil
---@return string? err nil on success
function PhilipsHueApi:get_all_reprs_for_rtype(rtype) return do_get(self, string.format("/clip/v2/resource/%s", string.lower(tostring(rtype)))) end

---@generic T: HueResourceInfo
---@param rtype string
---@param rid string
---@return HueResourceResponse<T>|nil
---@return string? err nil on success
function PhilipsHueApi:get_rtype_by_rid(rtype, rid)
  return do_get(
    self,
    string.format(
      "/clip/v2/resource/%s/%s",
      string.lower(tostring(rtype)),
      string.lower(tostring(rid))
    )
  )
end

---@return HueResourceResponse<HueLightInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_lights() return self:get_all_reprs_for_rtype(HueDeviceTypes.LIGHT) end

---@return HueResourceResponse<HueDeviceInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_devices() return self:get_all_reprs_for_rtype("device") end

---@return HueResourceResponse<HueZigbeeInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_connectivity_status() return self:get_all_reprs_for_rtype("zigbee_connectivity") end

---@param light_resource_id string
---@return HueResourceResponse<HueLightInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_light_by_id(light_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.LIGHT, light_resource_id)
end

---@param hue_device_id string
---@return HueResourceResponse<HueDeviceInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_device_by_id(hue_device_id)
  return self:get_rtype_by_rid("device", hue_device_id)
end

---@param zigbee_resource_id string
---@return HueResourceResponse<HueZigbeeInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_zigbee_connectivity_by_id(zigbee_resource_id)
  return self:get_rtype_by_rid("zigbee_connectivity", zigbee_resource_id)
end

---@param button_resource_id string
---@return HueResourceResponse<HueButtonInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_button_by_id(button_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.BUTTON, button_resource_id)
end

---@param contact_resource_id string
---@return HueResourceResponse<HueContactInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_contact_by_id(contact_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.CONTACT, contact_resource_id)
end

---@param motion_resource_id string
---@return HueResourceResponse<HueMotionInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_motion_by_id(motion_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.MOTION, motion_resource_id)
end

---@param device_power_resource_id string
---@return HueResourceResponse<HuePowerLevelInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_device_power_by_id(device_power_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.DEVICE_POWER, device_power_resource_id)
end

---@param tamper_resource_id string
---@return HueResourceResponse<HueTamperInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_tamper_by_id(tamper_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.TAMPER, tamper_resource_id)
end

---@param temperature_resource_id string
---@return HueResourceResponse<HueTemperatureInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_temperature_by_id(temperature_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.TEMPERATURE, temperature_resource_id)
end

---@param light_level_resource_id string
---@return HueResourceResponse<HueLightLevelInfo>?
---@return string? err nil on success
function PhilipsHueApi:get_light_level_by_id(light_level_resource_id)
  return self:get_rtype_by_rid(HueDeviceTypes.LIGHT_LEVEL, light_level_resource_id)
end

---@param id string
---@param on boolean
---@return { errors: table[], [string]: any }? response json payload in response to the request, nil on error
---@return string? err error, nil on successful HTTP request but the response may indicate a problem with the request itself.
function PhilipsHueApi:set_light_on_state(id, on)
  local url = string.format("/clip/v2/resource/%s/%s", HueDeviceTypes.LIGHT, id)

  if type(on) ~= "boolean" then
    if on then
      on = true
    else
      on = false
    end
  end

  local payload = json.encode { on = { on = on } }

  return do_put(self, url, payload)
end

---@param id string
---@param level number
---@return { errors: table[], [string]: any }? response json payload in response to the request, nil on error
---@return string? err error, nil on successful HTTP request but the response may indicate a problem with the request itself.
function PhilipsHueApi:set_light_level(id, level)
  if type(level) == "number" then
    local url = string.format("/clip/v2/resource/%s/%s", HueDeviceTypes.LIGHT, id)
    local payload_table = { dimming = { brightness = level } }

    return do_put(self, url, json.encode(payload_table))
  else
    return nil,
        string.format("Expected number for light level, received %s", st_utils.stringify_table(level, nil, false))
  end
end

---@param id string
---@param xy_table HueColorCoords
---@return { errors: table[], [string]: any }? response json payload in response to the request, nil on error
---@return string? err error, nil on successful HTTP request but the response may indicate a problem with the request itself.
function PhilipsHueApi:set_light_color_xy(id, xy_table)
  local x_valid = (xy_table ~= nil) and ((xy_table.x ~= nil) and (type(xy_table.x) == "number"))
  local y_valid = (xy_table ~= nil) and ((xy_table.y ~= nil) and (type(xy_table.y) == "number"))

  if x_valid and y_valid then
    local url = string.format("/clip/v2/resource/%s/%s", HueDeviceTypes.LIGHT, id)
    local payload = json.encode { color = { xy = xy_table }, on = { on = true } }
    return do_put(self, url, payload)
  else
    return nil,
        string.format("invalid XY color table for set_light_color_xy: %s", st_utils.stringify_table(xy_table, nil, false))
  end
end

---@param id string
---@param mirek number
---@return { errors: table[], [string]: any }? response json payload in response to the request, nil on error
---@return string? err error, nil on successful HTTP request but the response may indicate a problem with the request itself.
function PhilipsHueApi:set_light_color_temp(id, mirek)
  if type(mirek) == "number" then
    local url = string.format("/clip/v2/resource/%s/%s", HueDeviceTypes.LIGHT, id)
    local payload = json.encode { color_temperature = { mirek = mirek }, on = { on = true } }

    return do_put(self, url, payload)
  else
    return nil,
        string.format("Expected number for color temp mirek, received %s", st_utils.stringify_table(mirek, nil, false))
  end
end

return PhilipsHueApi
