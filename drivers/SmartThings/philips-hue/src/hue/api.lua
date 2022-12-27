local json = require "st.json"
local RestClient = require "lunchbox.rest"
local utils = require "st.utils"

local APPLICATION_KEY_HEADER = "hue-application-key"

--- Phillips Hue REST API Module
--- @class PhilipsHueApi
--- @field private client RestClient
--- @field private headers table<string,string>
local PhilipsHueApi = {}
PhilipsHueApi.__index = PhilipsHueApi

PhilipsHueApi.MIN_CLIP_V2_SWVERSION = 1948086000
PhilipsHueApi.MIN_TEMP_KELVIN = 2000
PhilipsHueApi.MAX_TEMP_KELVIN = 6500
PhilipsHueApi.APPLICATION_KEY_HEADER = APPLICATION_KEY_HEADER

local function retry_fn(retry_attempts)
  local count = 0
  return function()
    count = count + 1
    return count < retry_attempts
  end
end

function PhilipsHueApi.new_bridge_manager(base_url, api_key, socket_builder)
  return setmetatable(
    {
      headers = { [APPLICATION_KEY_HEADER] = api_key or "" },
      client = RestClient.new(base_url, socket_builder),
    }, PhilipsHueApi
  )
end

function PhilipsHueApi:update_connection(hub_base_url, api_key)
  self.client:update_base_url(hub_base_url)
  self.headers[APPLICATION_KEY_HEADER] = api_key
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

local function do_get(api_instance, path)
  return process_rest_response(api_instance.client:get(path, api_instance.headers, retry_fn(5)))
end

local function do_put(api_instance, path, payload)
  return process_rest_response(api_instance.client:put(path, payload, api_instance.headers, retry_fn(5)))
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

-- function PhilipsHueApi:get_configs()
--     return do_get(self, "/api/config")
-- end

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

function PhilipsHueApi:set_light_level(id, level, min_dim)
  if type(level) == "number" then
    local url = string.format("/clip/v2/resource/light/%s", id)
    level = math.floor(utils.clamp_value(level, min_dim, 100))
    local payload_table = { dimming = { brightness = level } }

    return do_put(self, url, json.encode(payload_table))
  else
    return nil, string.format("Expected number for light level, received %s", utils.stringify_table(level, nil, false))
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
        string.format("invalid XY color table for set_light_color_xy: %s", utils.stringify_table(xy_table, nil, false))
  end
end

function PhilipsHueApi:set_light_color_temp(id, mirek)
  if type(mirek) == "number" then
    local url = string.format("/clip/v2/resource/light/%s", id)
    local payload = json.encode { color_temperature = { mirek = mirek }, on = { on = true } }

    return do_put(self, url, payload)
  else
    return nil,
        string.format("Expected number for color temp mirek, received %s", utils.stringify_table(mirek, nil, false))
  end
end

return PhilipsHueApi
