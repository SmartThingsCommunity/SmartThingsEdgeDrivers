local cluster_base = require "st.matter.cluster_base"
local ConcentrationMeasurementServerAttributes = require "ConcentrationMeasurement.server.attributes"
local ConcentrationMeasurementTypes = require "ConcentrationMeasurement.types"

local ConcentrationMeasurement = {}

ConcentrationMeasurement.ID = 0x040C
ConcentrationMeasurement.NAME = "CarbonMonoxideConcentrationMeasurement"
ConcentrationMeasurement.server = {}
ConcentrationMeasurement.client = {}
ConcentrationMeasurement.server.attributes = ConcentrationMeasurementServerAttributes:set_parent_cluster(ConcentrationMeasurement)
ConcentrationMeasurement.types = ConcentrationMeasurementTypes

function ConcentrationMeasurement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "MeasuredValue",
    [0x0001] = "MinMeasuredValue",
    [0x0002] = "MaxMeasuredValue",
    [0x0003] = "PeakMeasuredValue",
    [0x0004] = "PeakMeasuredValueWindow",
    [0x0005] = "AverageMeasuredValue",
    [0x0006] = "AverageMeasuredValueWindow",
    [0x0007] = "Uncertainty",
    [0x0008] = "MeasurementUnit",
    [0x0009] = "MeasurementMedium",
    [0x000A] = "LevelValue",
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

function ConcentrationMeasurement:get_server_command_by_id(command_id)
  local server_id_map = {
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

ConcentrationMeasurement.attribute_direction_map = {
  ["MeasuredValue"] = "server",
  ["MinMeasuredValue"] = "server",
  ["MaxMeasuredValue"] = "server",
  ["PeakMeasuredValue"] = "server",
  ["PeakMeasuredValueWindow"] = "server",
  ["AverageMeasuredValue"] = "server",
  ["AverageMeasuredValueWindow"] = "server",
  ["Uncertainty"] = "server",
  ["MeasurementUnit"] = "server",
  ["MeasurementMedium"] = "server",
  ["LevelValue"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

ConcentrationMeasurement.command_direction_map = {
}

ConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function ConcentrationMeasurement.are_features_supported(feature, feature_map)
  if (ConcentrationMeasurement.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ConcentrationMeasurement.NAME))
  end
  return ConcentrationMeasurement[direction].attributes[key]
end
ConcentrationMeasurement.attributes = {}
setmetatable(ConcentrationMeasurement.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ConcentrationMeasurement.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ConcentrationMeasurement.NAME))
  end
  return ConcentrationMeasurement[direction].commands[key]
end
ConcentrationMeasurement.commands = {}
setmetatable(ConcentrationMeasurement.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return ConcentrationMeasurement.server.events[key]
end
ConcentrationMeasurement.events = {}
setmetatable(ConcentrationMeasurement.events, event_helper_mt)

setmetatable(ConcentrationMeasurement, {__index = cluster_base})

return ConcentrationMeasurement

