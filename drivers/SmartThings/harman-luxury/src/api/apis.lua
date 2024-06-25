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

--- get active credential token from a Harman Luxury device on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.InitCredentialsToken(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "initCredentialsToken")
end

--- get active credential token from a Harman Luxury device on ip
---@param ip string
---@return boolean|number|string|table|nil, nil|string
function APIs.GetCredentialsToken(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "getCredentialsToken")
end

--- get supported input sources from a Harman Luxury device on ip
---@param ip string
---@return table|nil, nil|string
function APIs.GetSupportedInputSources(ip)
  return invoke.Activate(ip, SMARTTHINGS_PATH .. "getSupportedInputSources")
end

return APIs
