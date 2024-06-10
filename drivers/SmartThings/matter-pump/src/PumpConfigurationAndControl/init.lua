local cluster_base = require "st.matter.cluster_base"
local PumpConfigurationAndControlServerAttributes = require "PumpConfigurationAndControl.server.attributes"
local PumpConfigurationAndControlTypes = require "PumpConfigurationAndControl.types"

local PumpConfigurationAndControl = {}

PumpConfigurationAndControl.ID = 0x0200
PumpConfigurationAndControl.NAME = "PumpConfigurationAndControl"
PumpConfigurationAndControl.server = {}
PumpConfigurationAndControl.client = {}
PumpConfigurationAndControl.server.attributes = PumpConfigurationAndControlServerAttributes:set_parent_cluster(PumpConfigurationAndControl)
PumpConfigurationAndControl.types = PumpConfigurationAndControlTypes

function PumpConfigurationAndControl:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "MaxPressure",
    [0x0001] = "MaxSpeed",
    [0x0002] = "MaxFlow",
    [0x0003] = "MinConstPressure",
    [0x0004] = "MaxConstPressure",
    [0x0005] = "MinCompPressure",
    [0x0006] = "MaxCompPressure",
    [0x0007] = "MinConstSpeed",
    [0x0008] = "MaxConstSpeed",
    [0x0009] = "MinConstFlow",
    [0x000A] = "MaxConstFlow",
    [0x000B] = "MinConstTemp",
    [0x000C] = "MaxConstTemp",
    [0x0010] = "PumpStatus",
    [0x0011] = "EffectiveOperationMode",
    [0x0012] = "EffectiveControlMode",
    [0x0013] = "Capacity",
    [0x0014] = "Speed",
    [0x0015] = "LifetimeRunningHours",
    [0x0016] = "Power",
    [0x0017] = "LifetimeEnergyConsumed",
    [0x0020] = "OperationMode",
    [0x0021] = "ControlMode",
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

PumpConfigurationAndControl.attribute_direction_map = {
  ["MaxPressure"] = "server",
  ["MaxSpeed"] = "server",
  ["MaxFlow"] = "server",
  ["MinConstPressure"] = "server",
  ["MaxConstPressure"] = "server",
  ["MinCompPressure"] = "server",
  ["MaxCompPressure"] = "server",
  ["MinConstSpeed"] = "server",
  ["MaxConstSpeed"] = "server",
  ["MinConstFlow"] = "server",
  ["MaxConstFlow"] = "server",
  ["MinConstTemp"] = "server",
  ["MaxConstTemp"] = "server",
  ["PumpStatus"] = "server",
  ["EffectiveOperationMode"] = "server",
  ["EffectiveControlMode"] = "server",
  ["Capacity"] = "server",
  ["Speed"] = "server",
  ["LifetimeRunningHours"] = "server",
  ["Power"] = "server",
  ["LifetimeEnergyConsumed"] = "server",
  ["OperationMode"] = "server",
  ["ControlMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

PumpConfigurationAndControl.FeatureMap = PumpConfigurationAndControl.types.Feature

function PumpConfigurationAndControl.are_features_supported(feature, feature_map)
  if (PumpConfigurationAndControl.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = PumpConfigurationAndControl.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, PumpConfigurationAndControl.NAME))
  end
  return PumpConfigurationAndControl[direction].attributes[key]
end
PumpConfigurationAndControl.attributes = {}
setmetatable(PumpConfigurationAndControl.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = PumpConfigurationAndControl.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, PumpConfigurationAndControl.NAME))
  end
  return PumpConfigurationAndControl[direction].commands[key]
end
PumpConfigurationAndControl.commands = {}
setmetatable(PumpConfigurationAndControl.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return PumpConfigurationAndControl.server.events[key]
end
PumpConfigurationAndControl.events = {}
setmetatable(PumpConfigurationAndControl.events, event_helper_mt)

setmetatable(PumpConfigurationAndControl, {__index = cluster_base})

return PumpConfigurationAndControl
