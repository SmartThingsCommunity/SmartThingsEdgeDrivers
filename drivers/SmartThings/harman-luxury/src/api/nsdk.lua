local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"
local url = require "net.url"
local json = require "st.json"
local net_utils = require "st.net_utils"
local st_utils = require "st.utils"
local log = require "log"

----------------------------------------------------------
--- Definitions
----------------------------------------------------------

local HTTP = "http://"
local GET_DATA = "/api/getData"
local GET_ROWS = "/api/getRows"
local SET_DATA = "/api/setData"

----------------------------------------------------------
--- Functions
----------------------------------------------------------

local NSDK = {}

--- Helpers ----------------------------------------------

--- formats a list of roles into a formatted string suitable for the HTTP API
---@param rolesList table<string>|nil
---@return string
local function format_roles(rolesList)
    if rolesList == nil then
        return "value"
    else
        local t = {}
        for _, role in rolesList do
            if role == "all" then
                return "@all"
            else
                table.insert(t, role)
            end
        end
        return table.concat(t, ",")
    end
end

--- creates a JSON error mesage from a string
---@class ErrMsg
---@field error table<string>
---@param msg string
---@return ErrMsg
local function error_msg(msg)
    return {
        error = {
            message = msg
        }
    }
end

--- Actual Functions -------------------------------------

--- API to send a GetData request to nSDK
---@param ip string
---@param path string
---@param roles string|table
---@return boolean, boolean|number|string|table|ErrMsg
local function _NsdkGetData(ip, path, roles)
    log.debug(string.format("Nsdk GetData: ip:%s path:%s", ip, path))
    local u = url.parse(string.format("%s%s%s", HTTP, ip, GET_DATA))
    u:setQuery{
        path = path,
        roles = roles
    }
    u = u:build()
    local sink = {}
    local result, code, _ = http.request {
        url = u,
        method = "GET",
        sink = ltn12.sink.table(sink)
    }
    if code == 200 then -- OK
        local ret, val = pcall(json.decode, table.concat(sink, ""))
        val = val[1]
        log.debug(string.format("Nsdk GetData: received value:%s", st_utils.stringify_table(val)))
        return ret, val
    elseif code == 500 then -- ERROR
        local ret, err = pcall(json.decode, sink[result])
        log.warn(string.format("Error in GetData: %s. Error: \"%s\"", u,
            (ret and "json.decode() failed" or err["error"]["message"])))
        return false, err
    else -- UNKNOWN VALUE
        local err = error_msg(string.format("Error in GetData: Unknown return value: %s - %s", code,
            st_utils.stringify_table(sink)))
        log.error(err["error"]["message"])
        return false, err
    end
end

--- API to send a GetRows request to nSDK
---@param ip string
---@param path string
---@param roles string
---@param from number
---@param to number
---@return boolean, boolean|number|string|table|ErrMsg
local function _NsdkGetRows(ip, path, roles, from, to)
    log.debug(string.format("Nsdk GetRows: ip:%s path:%s", ip, path))
    local u = url.parse(string.format("%s%s%s", HTTP, ip, GET_ROWS))
    u:setQuery{
        path = path,
        roles = roles,
        from = from,
        to = to
    }
    u = u:build()
    local sink = {}
    local result, code, _ = http.request {
        url = u,
        method = "GET",
        sink = ltn12.sink.table(sink)
    }
    if code == 200 then -- OK
        local ret, val = pcall(json.decode, table.concat(sink, ""))
        val = val[1]["rows"]
        log.debug(string.format("Nsdk GetRows: received value:%s", st_utils.stringify_table(val)))
        return ret, val
    elseif code == 500 then -- ERROR
        local ret, err = pcall(json.decode, sink[result])
        log.warn(string.format("Error in GetRows: URL: %s. Error: \"%s\"", u,
            (ret and "json.decode() failed" or err["error"]["message"])))
        return false, err
    else -- UNKNOWN VALUE
        local err = error_msg(string.format("Error in GetRows: Unknown return value: %s - %s", code,
            st_utils.stringify_table(sink)))
        log.error(err["error"]["message"])
        return false, err
    end
end

--- API to send a SetData request to nSDK
---@param ip string
---@param path string
---@param role string
---@param value string
---@return boolean, boolean|number|string|table|ErrMsg
local function _NsdkSetData(ip, path, role, value)
    log.debug(string.format("Nsdk SetData: ip:%s path:%s", ip, path))
    local u = url.parse(string.format("%s%s%s", HTTP, ip, SET_DATA))
    u:setQuery{
        path = path,
        role = role,
        value = value
    }
    u = u:build()
    local sink = {}
    local result, code, _ = http.request {
        url = u,
        method = "GET",
        sink = ltn12.sink.table(sink)
    }
    if code == 200 then -- OK
        local ret, val = pcall(json.decode, table.concat(sink, ""))
        log.debug(string.format("Nsdk SetData: received value:%s", st_utils.stringify_table(val)))
        return ret, val
    elseif code == 500 then -- ERROR
        local ret, err = pcall(json.decode, sink[result])
        log.warn(string.format("Error in SetData: URL: %s. Error: \"%s\"", u,
            (ret and "json.decode() failed" or err["error"]["message"])))
        return false, err
    else -- UNKNOWN VALUE
        local err = error_msg(string.format("Error in SetData: Unknown return value: %s - %s", code,
            st_utils.stringify_table(sink)))
        log.error(err["error"]["message"])
        return false, err
    end
end

--- Wrappers ----------------------------------------------------------

--- API to send a GetData request to nSDK
---@class GetInput
---@field ip string
---@field path string
---@field rolesList table<string>|nil
---@param arg GetInput
---@return boolean, boolean|number|string|table|ErrMsg
function NSDK.GetData(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        local err = error_msg(string.format("Error in GetData: Invalid IP! Given IP: ", arg.ip))
        log.error(err["error"]["message"])
        return false, err
    end
    if type(arg.path) ~= "string" then
        local err = error_msg(string.format("Error in GetData: Invalid Path! Given path: ", arg.path))
        log.error(err["error"]["message"])
        return false, err
    end
    local roles = format_roles(arg.rolesList)

    return _NsdkGetData(arg.ip, arg.path, roles)
end

--- API to send a GetRows request to nSDK
---@class GetRowsInput
---@field ip string
---@field path string
---@field rolesList table<string>|nil
---@field from number|nil
---@field to number|nil
---@param arg GetRowsInput
---@return boolean, boolean|number|string|table|ErrMsg
function NSDK.GetRows(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        local err = error_msg(string.format("Error in GetRows: Invalid IP! Given IP: ", arg.ip))
        log.error(err["error"]["message"])
        return false, err
    end
    if type(arg.path) ~= "string" then
        local err = error_msg(string.format("Error in GetRows: Invalid Path! Given path: ", arg.path))
        log.error(err["error"]["message"])
        return false, err
    end
    local from, to
    if type(arg.from) == "number" then
        from = arg.from
    else
        from = 0
    end
    if type(arg.to) == "number" then
        to = arg.to
    else
        to = 10
    end
    local roles = format_roles(arg.rolesList)

    return _NsdkGetRows(arg.ip, arg.path, roles, from, to)
end

--- API to send a SetData request to nSDK
---@class SetInput
---@field ip string
---@field path string
---@field value table
---@param arg SetInput
---@return boolean, boolean|number|string|table|ErrMsg
function NSDK.SetData(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        local err = error_msg(string.format("Error in SetData: Invalid IP! Given IP: ", arg.ip))
        log.error(err["error"]["message"])
        return false, err
    end
    if type(arg.path) ~= "string" then
        local err = error_msg(string.format("Error in SetData: Invalid Path! Given path: ", arg.path))
        log.error(err["error"]["message"])
        return false, err
    end
    local value
    if type(arg.value) ~= "table" then
        local err = error_msg("Error in SetData: Invalid value. Value needs to be given as a table!")
        log.error(err["error"]["message"])
        return false, err
    else
        value = json.encode(arg.value)
    end

    return _NsdkSetData(arg.ip, arg.path, "value", value)
end

--- API to send an Invoke request to nSDK
---@class InvokeInput
---@field ip string
---@field path string
---@field value table|nil
---@param arg InvokeInput
---@return boolean, boolean|number|string|table|ErrMsg
function NSDK.Invoke(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        local err = error_msg(string.format("Error in Invoke: Invalid IP! Given IP: ", arg.ip))
        log.error(err["error"]["message"])
        return false, err
    end
    if type(arg.path) ~= "string" then
        local err = error_msg(string.format("Error in Invoke: Invalid Path! Given path: ", arg.path))
        log.error(err["error"]["message"])
        return false, err
    end
    local value
    if type(arg.value) == "table" then
        value = json.encode(arg.value)
    elseif arg.value == nil then
        value = "{}"
    else
        local err = error_msg("Error in Invoke: Invalid value. If Value given, it needs to be given as a table!")
        log.error(err["error"]["message"])
        return false, err
    end
    return _NsdkSetData(arg.ip, arg.path, "activate", value)
end

return NSDK
