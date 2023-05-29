local cosock = require "cosock"
local channel = require "cosock.channel"

local json = require "st.json"
local log = require "log"
local RestClient = require "lunchbox.rest"
local st_utils = require "st.utils"

local APPLICATION_KEY_HEADER = "hue-application-key"

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

--- Phillips Hue REST API Module
--- @class PhilipsHueApi
--- @field private client RestClient
--- @field private headers table<string,string>
--- @field private _ctrl_tx table
local PhilipsHueApi = {}
PhilipsHueApi.__index = PhilipsHueApi
PhilipsHueApi.__gc = function(self)
  if self._running then
    self._ctrl_tx:send(ControlMessageBuilders.Shutdown())
    self._running = false
  end
end

PhilipsHueApi.MIN_CLIP_V2_SWVERSION = 1948086000
PhilipsHueApi.MIN_TEMP_KELVIN_COLOR_AMBIANCE = 2000
PhilipsHueApi.MIN_TEMP_KELVIN_WHITE_AMBIANCE = 2200
PhilipsHueApi.MAX_TEMP_KELVIN = 6500
PhilipsHueApi.APPLICATION_KEY_HEADER = APPLICATION_KEY_HEADER

local function retry_fn(retry_attempts)
  local count = 0
  return function()
    count = count + 1
    return count < retry_attempts
  end
end

local function process_rest_response(response, err, partial)
  if err ~= nil then
    return response, err, partial
  elseif response ~= nil then
    local body, err = response:get_body()
    if not body then
      return nil, err
    end
    return json.decode(body)
  else
    return nil, "no response or error received"
  end
end

function PhilipsHueApi.new_bridge_manager(base_url, api_key, socket_builder)
  local control_tx, control_rx = channel.new()
  local self = setmetatable(
    {
      headers = { [APPLICATION_KEY_HEADER] = api_key or "" },
      client = RestClient.new(base_url, socket_builder),
      _ctrl_tx = control_tx,
      _running = true
    }, PhilipsHueApi
  )

  cosock.spawn(function()
    while true do
      local msg, err = control_rx:receive()
      if err then
        log.error("Error receiving on control channel for REST API thread", err)
        goto continue
      end

      if msg and msg._type then
        if msg._type == ControlMessageTypes.Shutdown then
          log.trace("REST API Control Thread received shutdown message");
          self._running = false
          return
        end

        if msg._type == ControlMessageTypes.Update then
          self.client:update_base_url(msg.base_url)
          self.headers[APPLICATION_KEY_HEADER] = msg.api_key
          goto continue
        end

        local path, reply_tx = msg.path, msg.reply_tx
        if msg._type == ControlMessageTypes.Get then
          reply_tx:send(
            table.pack(process_rest_response(self.client:get(path, self.headers, retry_fn(5))))
          )
        elseif msg._type == ControlMessageTypes.Put then
          local payload = msg.payload
          reply_tx:send(
            table.pack(process_rest_response(self.client:put(path, payload, self.headers, retry_fn(5))))
          )
        end
      else
        log.warn(st_utils.stringify_table(msg, "Unexpected Message on REST API Control Channel", false))
      end

      ::continue::
    end
  end, string.format("Hue API Thread for %s", base_url))

  return self
end

function PhilipsHueApi:update_connection(hub_base_url, api_key)
  local msg = ControlMessageBuilders.Update(hub_base_url, api_key)
  self._ctrl_tx:send(msg)
end

local function do_get(instance, path)
  local reply_tx, reply_rx = channel.new()
  local msg = ControlMessageBuilders.Get(path, reply_tx);
  instance._ctrl_tx:send(msg)
  return table.unpack(reply_rx:receive())
end

local function do_put(instance, path, payload)
  local reply_tx, reply_rx = channel.new()
  local msg = ControlMessageBuilders.Put(path, payload, reply_tx);
  instance._ctrl_tx:send(msg)
  return table.unpack(reply_rx:receive())
end

---@param bridge_ip string
---@return HueBridgeInfo|nil bridge_info nil on err
---@return nil|string error nil on success
---@return nil|string partial partial response if available, nil otherwise
function PhilipsHueApi.get_bridge_info(bridge_ip)
  return process_rest_response(RestClient.one_shot_get("https://" .. bridge_ip .. "/api/config", nil, nil))
end

function PhilipsHueApi.request_api_key(bridge_ip)
  local body = json.encode { devicetype = "smartthings_edge_driver#" .. bridge_ip, generateclientkey = true }
  return process_rest_response(RestClient.one_shot_post("https://" .. bridge_ip .. "/api", body, nil, nil))
end

function PhilipsHueApi:get_lights() return do_get(self, "/clip/v2/resource/light") end

function PhilipsHueApi:get_devices() return do_get(self, "/clip/v2/resource/device") end

function PhilipsHueApi:get_rooms() return do_get(self, "/clip/v2/resource/room") end

function PhilipsHueApi:get_light_by_id(id)
  return do_get(self, string.format("/clip/v2/resource/light/%s", id))
end

function PhilipsHueApi:get_room_by_id(id)
  return do_get(self, string.format("/clip/v2/resource/room/%s", id))
end

function PhilipsHueApi:set_light_on_state(id, on)
  local url = string.format("/clip/v2/resource/light/%s", id)

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

function PhilipsHueApi:set_light_level(id, level)
  if type(level) == "number" then
    local url = string.format("/clip/v2/resource/light/%s", id)
    local payload_table = { dimming = { brightness = level } }

    return do_put(self, url, json.encode(payload_table))
  else
    return nil,
        string.format("Expected number for light level, received %s", st_utils.stringify_table(level, nil, false))
  end
end

function PhilipsHueApi:set_light_color_xy(id, xy_table)
  local x_valid = (xy_table ~= nil) and ((xy_table.x ~= nil) and (type(xy_table.x) == "number"))
  local y_valid = (xy_table ~= nil) and ((xy_table.y ~= nil) and (type(xy_table.y) == "number"))

  if x_valid and y_valid then
    local url = string.format("/clip/v2/resource/light/%s", id)
    local payload = json.encode { color = { xy = xy_table }, on = { on = true } }
    return do_put(self, url, payload)
  else
    return nil,
        string.format("invalid XY color table for set_light_color_xy: %s", st_utils.stringify_table(xy_table, nil, false))
  end
end

function PhilipsHueApi:set_light_color_temp(id, mirek)
  if type(mirek) == "number" then
    local url = string.format("/clip/v2/resource/light/%s", id)
    local payload = json.encode { color_temperature = { mirek = mirek }, on = { on = true } }

    return do_put(self, url, payload)
  else
    return nil,
        string.format("Expected number for color temp mirek, received %s", st_utils.stringify_table(mirek, nil, false))
  end
end

return PhilipsHueApi
