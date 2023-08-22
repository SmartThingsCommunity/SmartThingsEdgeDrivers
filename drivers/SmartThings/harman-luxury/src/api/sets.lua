local nsdk = require "api.nsdk"

local Sets = {}

----------------------------------------------------------
--- Helper Functions
----------------------------------------------------------

--- set value from path in ip
---@param ip string
---@param path string
---@param type string
---@param value boolean|number|string
---@return boolean, boolean|number|string|table|ErrMsg
local function SetValue(ip, path, type, value)
	local table_value = {
		type = type,
		[type] = value
	}
	return nsdk.SetData {
		ip = ip,
		path = path,
		value = table_value
	}
end

----------------------------------------------------------
--- SetTYPE Functions
----------------------------------------------------------

--- set bool value from path in ip
---@param ip string
---@param path string
---@param value boolean
---@return boolean, boolean|number|string|table|ErrMsg
function Sets.Bool(ip, path, value)
	return SetValue(ip, path, "bool_", value)
end

--- set byte value from path in ip
---@param ip string
---@param path string
---@param value number
---@return boolean, boolean|number|string|table|ErrMsg
function Sets.Byte(ip, path, value)
	return SetValue(ip, path, "byte_", value)
end

--- set i16 value from path in ip
---@param ip string
---@param path string
---@param value number
---@return boolean, boolean|number|string|table|ErrMsg
function Sets.I16(ip, path, value)
	return SetValue(ip, path, "i16_", value)
end

--- set i32 value from path in ip
---@param ip string
---@param path string
---@param value number
---@return boolean, boolean|number|string|table|ErrMsg
function Sets.I32(ip, path, value)
	return SetValue(ip, path, "i32_", value)
end

--- set i64 value from path in ip
---@param ip string
---@param path string
---@param value number
---@return boolean, boolean|number|string|table|ErrMsg
function Sets.I64(ip, path, value)
	return SetValue(ip, path, "i64_", value)
end

--- set double value from path in ip
---@param ip string
---@param path string
---@param value number
---@return boolean, boolean|number|string|table|ErrMsg
function Sets.Double(ip, path, value)
	return SetValue(ip, path, "double_", value)
end

--- set string value from path in ip
---@param ip string
---@param path string
---@param value string
---@return boolean, boolean|number|string|table|ErrMsg
function Sets.String(ip, path, value)
	return SetValue(ip, path, "string_", value)
end

return Sets
