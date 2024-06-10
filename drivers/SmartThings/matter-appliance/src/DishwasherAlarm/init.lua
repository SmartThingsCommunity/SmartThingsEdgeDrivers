local cluster_base = require "st.matter.cluster_base"
local DishwasherAlarmServerAttributes = require "DishwasherAlarm.server.attributes"
local DishwasherAlarmTypes = require "DishwasherAlarm.types"

local DishwasherAlarm = {}

DishwasherAlarm.ID = 0x005D
DishwasherAlarm.NAME = "DishwasherAlarm"
DishwasherAlarm.server = {}
DishwasherAlarm.client = {}
DishwasherAlarm.server.attributes = DishwasherAlarmServerAttributes:set_parent_cluster(DishwasherAlarm)
DishwasherAlarm.types = DishwasherAlarmTypes

function DishwasherAlarm:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "Mask",
    [0x0001] = "Latch",
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

function DishwasherAlarm:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "Reset",
    [0x0001] = "ModifyEnabledAlarms",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function DishwasherAlarm:get_event_by_id(event_id)
  local event_id_map = {
    [0x0000] = "Notify",
  }
  if event_id_map[event_id] ~= nil then
    return self.server.events[event_id_map[event_id]]
  end
  return nil
end

DishwasherAlarm.attribute_direction_map = {
  ["Mask"] = "server",
  ["Latch"] = "server",
  ["State"] = "server",
  ["Supported"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

DishwasherAlarm.command_direction_map = {
  ["Reset"] = "server",
  ["ModifyEnabledAlarms"] = "server",
}

DishwasherAlarm.FeatureMap = DishwasherAlarm.types.Feature

function DishwasherAlarm.are_features_supported(feature, feature_map)
  if (DishwasherAlarm.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = DishwasherAlarm.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, DishwasherAlarm.NAME))
  end
  return DishwasherAlarm[direction].attributes[key]
end
DishwasherAlarm.attributes = {}
setmetatable(DishwasherAlarm.attributes, attribute_helper_mt)

setmetatable(DishwasherAlarm, {__index = cluster_base})

return DishwasherAlarm

