local nsdk = require "api.nsdk"

Invokes = {}

----------------------------------------------------------
--- Functions
----------------------------------------------------------

--- set value from path in ip
---@param ip string
---@param path string
function Invokes.Activate(ip, path)
	local ret = nsdk.Invoke {
		ip = ip,
		path = path
	}
	if ret then
		return ret
	else
		return false
	end
end

--- set value from path in ip
---@param ip string
---@param path string
---@param value table
function Invokes.ActivateValue(ip, path, value)
	local ret = nsdk.Invoke {
		ip = ip,
		path = path,
		value = value
	}
	if ret then
		return ret
	else
		return false
	end
end

return Invokes
