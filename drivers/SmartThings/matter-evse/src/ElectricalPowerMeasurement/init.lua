local cluster_base = require "st.matter.cluster_base"
local ElectricalPowerMeasurementServerAttributes = require "ElectricalPowerMeasurement.server.attributes"
local ElectricalPowerMeasurementServerCommands = require "ElectricalPowerMeasurement.server.commands"
local ElectricalPowerMeasurementEvents = require "ElectricalPowerMeasurement.server.events"
local ElectricalPowerMeasurementTypes = require "ElectricalPowerMeasurement.types"

local ElectricalPowerMeasurement = {}

ElectricalPowerMeasurement.ID = 0x0090
ElectricalPowerMeasurement.NAME = "ElectricalPowerMeasurement"
ElectricalPowerMeasurement.server = {}
ElectricalPowerMeasurement.client = {}
ElectricalPowerMeasurement.server.attributes = ElectricalPowerMeasurementServerAttributes:set_parent_cluster(ElectricalPowerMeasurement)
ElectricalPowerMeasurement.server.commands = ElectricalPowerMeasurementServerCommands:set_parent_cluster(ElectricalPowerMeasurement)
ElectricalPowerMeasurement.server.events = ElectricalPowerMeasurementEvents:set_parent_cluster(ElectricalPowerMeasurement)
ElectricalPowerMeasurement.types = ElectricalPowerMeasurementTypes

local GLOBAL_CLUSTER_REVISION_ATTRIBUTE = 0xFFFD

local global_attr_id_map = {
  [GLOBAL_CLUSTER_REVISION_ATTRIBUTE] = {"cluster revision"},
}

ElectricalPowerMeasurement.FeatureMap = ElectricalPowerMeasurement.types.Feature

function ElectricalPowerMeasurement.are_features_supported(feature, feature_map)
  if (ElectricalPowerMeasurement.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

function ElectricalPowerMeasurement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "PowerMode",
    [0x0001] = "NumberOfMeasurementTypes",
    [0x0002] = "Accuracy",
    [0x0003] = "Ranges",
    [0x0004] = "Voltage",
    [0x0005] = "ActiveCurrent",
    [0x0006] = "ReactiveCurrent",
    [0x0007] = "ApparentCurrent",
    [0x0008] = "ActivePower",
    [0x0009] = "ReactivePower",
    [0x000A] = "ApparentPower",
    [0x000B] = "RMSVoltage",
    [0x000C] = "RMSCurrent",
    [0x000D] = "RMSPower",
    [0x000E] = "Frequency",
    [0x000F] = "HarmonicCurrents",
    [0x0010] = "HarmonicPhases",
    [0x0011] = "PowerFactor",
    [0x0012] = "NeutralCurrent",
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

function ElectricalPowerMeasurement:get_server_command_by_id(command_id)
  local server_id_map = {
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end


function ElectricalPowerMeasurement:get_event_by_id(event_id)
  local event_id_map = {
    [0x0000] = "MeasurementPeriodRanges",
  }
  if event_id_map[event_id] ~= nil then
    return self.server.events[event_id_map[event_id]]
  end
  return nil
end
-- Attribute Mapping
ElectricalPowerMeasurement.attribute_direction_map = {
  ["PowerMode"] = "server",
  ["NumberOfMeasurementTypes"] = "server",
  ["Accuracy"] = "server",
  ["Ranges"] = "server",
  ["Voltage"] = "server",
  ["ActiveCurrent"] = "server",
  ["ReactiveCurrent"] = "server",
  ["ApparentCurrent"] = "server",
  ["ActivePower"] = "server",
  ["ReactivePower"] = "server",
  ["ApparentPower"] = "server",
  ["RMSVoltage"] = "server",
  ["RMSCurrent"] = "server",
  ["RMSPower"] = "server",
  ["Frequency"] = "server",
  ["HarmonicCurrents"] = "server",
  ["HarmonicPhases"] = "server",
  ["PowerFactor"] = "server",
  ["NeutralCurrent"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

-- Command Mapping
ElectricalPowerMeasurement.command_direction_map = {
}

-- Cluster Completion
local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ElectricalPowerMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ElectricalPowerMeasurement.NAME))
  end
  return ElectricalPowerMeasurement[direction].attributes[key]
end
ElectricalPowerMeasurement.attributes = {}
setmetatable(ElectricalPowerMeasurement.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ElectricalPowerMeasurement.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ElectricalPowerMeasurement.NAME))
  end
  return ElectricalPowerMeasurement[direction].commands[key] 
end
ElectricalPowerMeasurement.commands = {}
setmetatable(ElectricalPowerMeasurement.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return ElectricalPowerMeasurement.server.events[key]
end
ElectricalPowerMeasurement.events = {}
setmetatable(ElectricalPowerMeasurement.events, event_helper_mt)

setmetatable(ElectricalPowerMeasurement, {__index = cluster_base})

return ElectricalPowerMeasurement
