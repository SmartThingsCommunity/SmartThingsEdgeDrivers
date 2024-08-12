local cluster_base = require "st.matter.cluster_base"
local RadonConcentrationMeasurementServerAttributes = require "RadonConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local RadonConcentrationMeasurement = {}

RadonConcentrationMeasurement.ID = 0x042F
RadonConcentrationMeasurement.NAME = "RadonConcentrationMeasurement"
RadonConcentrationMeasurement.server = {}
RadonConcentrationMeasurement.client = {}
RadonConcentrationMeasurement.server.attributes = RadonConcentrationMeasurementServerAttributes:set_parent_cluster(RadonConcentrationMeasurement)
RadonConcentrationMeasurement.types = ConcentrationMeasurement.types

function RadonConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function RadonConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

RadonConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

RadonConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function RadonConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = RadonConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, RadonConcentrationMeasurement.NAME))
  end
  return RadonConcentrationMeasurement[direction].attributes[key]
end
RadonConcentrationMeasurement.attributes = {}
setmetatable(RadonConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(RadonConcentrationMeasurement, {__index = cluster_base})

return RadonConcentrationMeasurement

