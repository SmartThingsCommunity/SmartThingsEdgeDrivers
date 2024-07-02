local cluster_base = require "st.matter.cluster_base"
local Pm10ConcentrationMeasurementServerAttributes = require "Pm10ConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local Pm10ConcentrationMeasurement = {}

Pm10ConcentrationMeasurement.ID = 0x042D
Pm10ConcentrationMeasurement.NAME = "Pm10ConcentrationMeasurement"
Pm10ConcentrationMeasurement.server = {}
Pm10ConcentrationMeasurement.client = {}
Pm10ConcentrationMeasurement.server.attributes = Pm10ConcentrationMeasurementServerAttributes:set_parent_cluster(Pm10ConcentrationMeasurement)
Pm10ConcentrationMeasurement.types = ConcentrationMeasurement.types

function Pm10ConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function Pm10ConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

Pm10ConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

Pm10ConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function Pm10ConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = Pm10ConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, Pm10ConcentrationMeasurement.NAME))
  end
  return Pm10ConcentrationMeasurement[direction].attributes[key]
end
Pm10ConcentrationMeasurement.attributes = {}
setmetatable(Pm10ConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(Pm10ConcentrationMeasurement, {__index = cluster_base})

return Pm10ConcentrationMeasurement

