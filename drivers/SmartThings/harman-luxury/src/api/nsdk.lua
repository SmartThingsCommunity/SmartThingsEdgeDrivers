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

NSDK = {}

--- Helpers ----------------------------------------------

--- formats a list of roles into a formatted string suitable for the HTTP API
---@param rolesList table
local function format_roles(rolesList)
    if rolesList == nil then
        return "value"
    else
        local roles = ""
        for i, role in rolesList do
            if roles == "all" then
                return "@all"
            else
                roles = roles .. role .. ","
            end
        end
        return roles:sub(1, -2)
    end
end

--- Actual Functions -------------------------------------

--- API to send a GetData request to nSDK
---@param ip string
---@param path string
---@param roles string
local function _NsdkGetData(ip, path, roles)
    log.debug(string.format("Nsdk GetData: ip:%s path:%s", ip, path))
    local u = url.parse(HTTP .. ip .. GET_DATA)
    u:setQuery {
        path = path,
        roles = roles
    }
    u = u:build()
    local sink = {}
    local result, code, headers = http.request {
        url = u,
        method = "GET",
        sink = ltn12.sink.table(sink)
    }
    if code == 200 then     -- OK
        return json.decode(sink[1])[1]
    elseif code == 500 then -- ERROR
        log.warn(string.format("Error in GetData: %s. Error: \"%s\"", u, json.decode(sink[result])["error"]["message"]))
        return false
    else -- UNKNOWN VALUE
        log.error(string.format("Error in GetData: Unknown return value: %s - %s", code, st_utils.stringify_table(sink)))
        return false
    end
end

--- API to send a GetRows request to nSDK
---@param ip string
---@param path string
---@param roles string
---@param from number
---@param to number
local function _NsdkGetRows(ip, path, roles, from, to)
    log.debug(string.format("Nsdk GetRows: ip:%s path:%s", ip, path))
    local u = url.parse(HTTP .. ip .. GET_ROWS)
    u:setQuery {
        path = path,
        roles = roles,
        from = from,
        to = to
    }
    u = u:build()
    local sink = {}
    local result, code, headers = http.request {
        url = u,
        method = "GET",
        sink = ltn12.sink.table(sink)
    }
    if code == 200 then     -- OK
        return json.decode(sink[1])[1]["rows"]
    elseif code == 500 then -- ERROR
        log.warn(string.format("Error in GetRows: URL: %s. Error: \"%s\"", u,
            json.decode(sink[result])["error"]["message"]))
        return false
    else -- UNKNOWN VALUE
        log.error(string.format("Error in GetRows: Unknown return value: %s - %s", code, st_utils.stringify_table(sink)))
        return false
    end
end

--- API to send a SetData request to nSDK
---@param ip string
---@param path string
---@param role string
---@param value string
local function _NsdkSetData(ip, path, role, value)
    log.debug(string.format("Nsdk SetData: ip:%s path:%s", ip, path))
    local u = url.parse(HTTP .. ip .. SET_DATA)
    u:setQuery {
        path = path,
        role = role,
        value = value
    }
    u = u:build()
    local sink = {}
    local result, code, headers = http.request {
        url = u,
        method = "GET",
        sink = ltn12.sink.table(sink)
    }
    if code == 200 then     -- OK
        return json.decode(sink[1])
    elseif code == 500 then -- ERROR
        log.warn(string.format("Error in SetData: URL: %s. Error: \"%s\"", u,
            json.decode(sink[result])["error"]["message"]))
        return false
    else -- UNKNOWN VALUE
        log.error(string.format("Error in SetData: Unknown return value: %s - %s", code, st_utils.stringify_table(sink)))
        return false
    end
end

--- Wrappers ----------------------------------------------------------

--- API to send a GetData request to nSDK
---@param arg table
---@param arg.ip string
---@param arg.path string
---@param arg.rolesList string|table [optional]
function NSDK.GetData(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        log.error(string.format("Error in GetData: Invalid IP! Given IP: ", arg.ip))
        return false
    end
    if type(arg.path) ~= "string" then
        log.error(string.format("Error in GetData: Invalid Path! Given path: ", arg.path))
        return false
    end
    local roles = format_roles(arg.rolesList)

    return _NsdkGetData(arg.ip, arg.path, roles)
end

--- API to send a GetRows request to nSDK
---@param arg table
---@param arg.ip string
---@param arg.path string
---@param arg.rolesList string|table [optional]
---@param arg.from number [optional]
---@param arg.to number [optional]
function NSDK.GetRows(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        log.error(string.format("Error in GetRows: Invalid IP! Given IP: ", arg.ip))
        return false
    end
    if type(arg.path) ~= "string" then
        log.error(string.format("Error in GetRows: Invalid Path! Given path: ", arg.path))
        return false
    end
    local from, to
    if arg.from == nil then
        from = 0
    else
        from = arg.from
    end
    if arg.to == nil then
        to = 10
    else
        to = arg.to
    end
    local roles = format_roles(arg.rolesList)

    return _NsdkGetRows(arg.ip, arg.path, roles, from, to)
end

--- API to send a SetData request to nSDK
---@param arg table
---@param arg.ip string
---@param arg.path string
---@param arg.value table
function NSDK.SetData(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        log.error(string.format("Error in SetData: Invalid IP! Given IP: ", arg.ip))
        return false
    end
    if type(arg.path) ~= "string" then
        log.error(string.format("Error in SetData: Invalid Path! Given path: ", arg.path))
        return false
    end
    local value
    if type(arg.value) ~= "table" then
        log.error("Error in SetData: Invalid value. Value needs to be given as a table!")
        return false
    else
        value = json.encode(arg.value)
    end

    return _NsdkSetData(arg.ip, arg.path, "value", value)
end

--- API to send an Invoke request to nSDK
---@param arg table
---@param arg.ip string
---@param arg.path string
---@param arg.value table|nil
function NSDK.Invoke(arg)
    if not net_utils.validate_ipv4_string(arg.ip) then
        log.error(string.format("Error in Invoke: Invalid IP! Given IP: ", arg.ip))
        return false
    end
    if type(arg.path) ~= "string" then
        log.error(string.format("Error in Invoke: Invalid Path! Given path: ", arg.path))
        return false
    end
    local value
    if type(arg.value) == "table" then
        value = json.encode(arg.value)
    elseif arg.value == nil then
        value = "{}"
    else
        log.error("Error in Invoke: Invalid value. If Value given, it needs to be given as a table!")
        return false
    end
    return _NsdkSetData(arg.ip, arg.path, "activate", value)
end

return NSDK
