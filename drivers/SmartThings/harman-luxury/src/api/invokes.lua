local nsdk = require "api.nsdk"

local Invokes = {}

----------------------------------------------------------
--- Functions
----------------------------------------------------------

--- set value from path in ip
---@param ip string
---@param path string
---@return boolean, boolean|number|string|table|ErrMsg
function Invokes.Activate(ip, path)
  return nsdk.Invoke {
    ip = ip,
    path = path
  }
end

--- set value from path in ip
---@param ip string
---@param path string
---@param value table
---@return boolean, boolean|number|string|table|ErrMsg
function Invokes.ActivateValue(ip, path, value)
  return nsdk.Invoke {
    ip = ip,
    path = path,
    value = value
  }
end

return Invokes
