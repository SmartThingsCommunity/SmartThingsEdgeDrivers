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

return utils
