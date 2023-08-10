local nsdk = require "api.nsdk"

Sets = {}

----------------------------------------------------------
--- Helper Functions
----------------------------------------------------------

--- set value from path in ip
---@param ip string
---@param path string
---@param type string
---@param value boolean|number|string
local function SetValue(ip, path, type, value)
	local table_value = {
		type = type,
		[type] = value
	}
	local ret = nsdk.SetData {
		ip = ip,
		path = path,
		value = table_value
	}
	if ret then
		return ret
	else
		return false
	end
end

----------------------------------------------------------
--- SetTYPE Functions
----------------------------------------------------------

--- set bool value from path in ip
---@param ip string
---@param path string
---@param value boolean
function Sets.Bool(ip, path, value)
	return SetValue(ip, path, "bool_", value)
end

--- set byte value from path in ip
---@param ip string
---@param path string
---@param value number
function Sets.Byte(ip, path, value)
	return SetValue(ip, path, "byte_", value)
end

--- set i16 value from path in ip
---@param ip string
---@param path string
---@param value number
function Sets.I16(ip, path, value)
	return SetValue(ip, path, "i16_", value)
end

--- set i32 value from path in ip
---@param ip string
---@param path string
---@param value number
function Sets.I32(ip, path, value)
	return SetValue(ip, path, "i32_", value)
end

--- set i64 value from path in ip
---@param ip string
---@param path string
---@param value number
function Sets.I64(ip, path, value)
	return SetValue(ip, path, "i64_", value)
end

--- set double value from path in ip
---@param ip string
---@param path string
---@param value number
function Sets.Double(ip, path, value)
	return SetValue(ip, path, "double_", value)
end

--- set string value from path in ip
---@param ip string
---@param path string
---@param value string
function Sets.String(ip, path, value)
	return SetValue(ip, path, "string_", value)
end

return Sets
