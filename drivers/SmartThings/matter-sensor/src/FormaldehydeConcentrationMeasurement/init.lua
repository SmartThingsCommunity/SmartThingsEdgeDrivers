local cluster_base = require "st.matter.cluster_base"
local FormaldehydeConcentrationMeasurementServerAttributes = require "FormaldehydeConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local FormaldehydeConcentrationMeasurement = {}

FormaldehydeConcentrationMeasurement.ID = 0x042B
FormaldehydeConcentrationMeasurement.NAME = "FormaldehydeConcentrationMeasurement"
FormaldehydeConcentrationMeasurement.server = {}
FormaldehydeConcentrationMeasurement.client = {}
FormaldehydeConcentrationMeasurement.server.attributes = FormaldehydeConcentrationMeasurementServerAttributes:set_parent_cluster(FormaldehydeConcentrationMeasurement)
FormaldehydeConcentrationMeasurement.types = ConcentrationMeasurement.types

function FormaldehydeConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function FormaldehydeConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

FormaldehydeConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

FormaldehydeConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function FormaldehydeConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = FormaldehydeConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, FormaldehydeConcentrationMeasurement.NAME))
  end
  return FormaldehydeConcentrationMeasurement[direction].attributes[key]
end
FormaldehydeConcentrationMeasurement.attributes = {}
setmetatable(FormaldehydeConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(FormaldehydeConcentrationMeasurement, {__index = cluster_base})

return FormaldehydeConcentrationMeasurement

