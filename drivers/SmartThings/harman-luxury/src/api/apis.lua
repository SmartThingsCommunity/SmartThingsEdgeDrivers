local get = require "api.gets"
local set = require "api.sets"
local invoke = require "api.invokes"

----------------------------------------------------------
--- Definitions
----------------------------------------------------------

--- system paths -----------------------------------------

local MANUFACTURER_NAME_PATH = "settings:/system/manufacturer"
local DEVICE_NAME_PATH = "settings:/deviceName"
local MODEL_NAME_PATH = "settings:/system/modelName"
local PRODUCT_NAME_PATH = "settings:/system/productName"
local INIT_CREDENTIAL_PATH = "smartthings:initCredentialsToken"
local CREDENTIAL_PATH = "settings:/smartthings/userToken"

----------------------------------------------------------
--- APIs
----------------------------------------------------------

local APIs = {}

--- system APIs ------------------------------------------

--- get device manufacturer name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetManufacturerName(ip)
  return get.String(ip, MANUFACTURER_NAME_PATH)
end

--- get device name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetDeviceName(ip)
  return get.String(ip, DEVICE_NAME_PATH)
end

--- get model name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetModelName(ip)
  return get.String(ip, MODEL_NAME_PATH)
end

--- get product name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetProductName(ip)
  return get.String(ip, PRODUCT_NAME_PATH)
end

--- set product name from Harman Luxury on ip
---@param ip string
---@param value string
---@return boolean|number|string|table|nil, nil|string
function APIs.SetDeviceName(ip, value)
  return set.String(ip, DEVICE_NAME_PATH, value)
end

--- initialise a new credential token from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.init_credential_token(ip)
  local val, err = invoke.Activate(ip, INIT_CREDENTIAL_PATH)
  if err then
    return nil, err
  else
    if type(val) == "string" then
      return val, nil
    else
      err = string.format("Device with IP:%s failed to generate a valid credential", ip)
      return nil, err
    end
  end
end

--- get device current active token from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetActiveCredentialToken(ip)
  return get.String(ip, CREDENTIAL_PATH)
end

return APIs
