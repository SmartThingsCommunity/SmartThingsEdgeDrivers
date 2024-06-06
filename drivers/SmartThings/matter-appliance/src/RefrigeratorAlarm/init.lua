local RefrigeratorAlarmServerAttributes = require "RefrigeratorAlarm.server.attributes"
local RefrigeratorAlarmTypes = require "RefrigeratorAlarm.types"

local RefrigeratorAlarm = {}

RefrigeratorAlarm.ID = 0x0057
RefrigeratorAlarm.NAME = "RefrigeratorAlarm"
RefrigeratorAlarm.server = {}
RefrigeratorAlarm.client = {}
RefrigeratorAlarm.server.attributes = RefrigeratorAlarmServerAttributes:set_parent_cluster(RefrigeratorAlarm)
RefrigeratorAlarm.types = RefrigeratorAlarmTypes

function RefrigeratorAlarm:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "Mask",
    [0x0002] = "State",
    [0x0003] = "Supported",
    [0xFFF9] = "AcceptedCommandList",
    [0xFFFA] = "EventList",
    [0xFFFB] = "AttributeList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

-- Attribute Mapping
RefrigeratorAlarm.attribute_direction_map = {
  ["Mask"] = "server",
  ["State"] = "server",
  ["Supported"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

-- Command Mapping
RefrigeratorAlarm.command_direction_map = {
}

-- Cluster Completion
local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = RefrigeratorAlarm.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, RefrigeratorAlarm.NAME))
  end
  return RefrigeratorAlarm[direction].attributes[key]
end
RefrigeratorAlarm.attributes = {}
setmetatable(RefrigeratorAlarm.attributes, attribute_helper_mt)

return RefrigeratorAlarm

