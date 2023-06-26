---@module 'utils'
local utils = {}

local MAC_ADDRESS_STR_LEN = 12

function utils.str_starts_with(str, start)
  return str:sub(1, #start) == start
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_edge_bridge(device)
  return device.device_network_id and #device.device_network_id == MAC_ADDRESS_STR_LEN and not (device.data and device.data.username)
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_edge_light(device)
  return device.parent_assigned_child_key and #device.parent_assigned_child_key > MAC_ADDRESS_STR_LEN and not (device.data and device.data.username and device.data.bulbId)
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_dth_bridge(device)
  return device.data ~= nil
      and not device.data.bulbId
      and device.data.username ~= nil
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_dth_light(device)
  return device.data ~= nil
      and device.data.bulbId ~= nil
      and device.data.username ~= nil
end

function utils.log_func_wrapper(func, func_name, log_level)
  local log = require "log"
  local st_utils = require "st.utils"
  log_level = log_level or log.LOG_LEVEL_INFO
  local wrapped_f = function(...)
    local args = {...}
    local log_str = "call to " .. func_name .. ": \n"
    for i, a in ipairs(args) do
      local arg_string = "    "
      if type(a) == "table" and a.pretty_print ~= nil then
        arg_string = arg_string .. a:pretty_print()
      elseif type(a) == "table" and a.NAME then
        arg_string = arg_string .. "table NAME: "..a.NAME
      else
        arg_string = arg_string .. st_utils.stringify_table(a)
      end

      -- Truncate extremely long args except for TRACE log level
      if #arg_string > 100 and log_level ~= log.LOG_LEVEL_TRACE then
        arg_string = string.sub(arg_string, 1, 101)
      end
      log_str = log_str .. arg_string .. "\n"
    end
    log.log({hub_logs = true}, log_level, log_str)
    return func(table.unpack(args))
  end
  return wrapped_f
end

return utils
