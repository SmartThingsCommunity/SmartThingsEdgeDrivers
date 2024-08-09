local cluster_base = require "st.matter.cluster_base"
local Pm25ConcentrationMeasurementServerAttributes = require "Pm25ConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local Pm25ConcentrationMeasurement = {}

Pm25ConcentrationMeasurement.ID = 0x042A
Pm25ConcentrationMeasurement.NAME = "Pm25ConcentrationMeasurement"
Pm25ConcentrationMeasurement.server = {}
Pm25ConcentrationMeasurement.client = {}
Pm25ConcentrationMeasurement.server.attributes = Pm25ConcentrationMeasurementServerAttributes:set_parent_cluster(Pm25ConcentrationMeasurement)
Pm25ConcentrationMeasurement.types = ConcentrationMeasurement.types

function Pm25ConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function Pm25ConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

Pm25ConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

Pm25ConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function Pm25ConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = Pm25ConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, Pm25ConcentrationMeasurement.NAME))
  end
  return Pm25ConcentrationMeasurement[direction].attributes[key]
end
Pm25ConcentrationMeasurement.attributes = {}
setmetatable(Pm25ConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(Pm25ConcentrationMeasurement, {__index = cluster_base})

return Pm25ConcentrationMeasurement

