local cluster_base = require "st.matter.cluster_base"
local Pm1ConcentrationMeasurementServerAttributes = require "Pm1ConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local Pm1ConcentrationMeasurement = {}

Pm1ConcentrationMeasurement.ID = 0x042C
Pm1ConcentrationMeasurement.NAME = "Pm1ConcentrationMeasurement"
Pm1ConcentrationMeasurement.server = {}
Pm1ConcentrationMeasurement.client = {}
Pm1ConcentrationMeasurement.server.attributes = Pm1ConcentrationMeasurementServerAttributes:set_parent_cluster(Pm1ConcentrationMeasurement)
Pm1ConcentrationMeasurement.types = ConcentrationMeasurement.types

function Pm1ConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function Pm1ConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

Pm1ConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

Pm1ConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function Pm1ConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = Pm1ConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, Pm1ConcentrationMeasurement.NAME))
  end
  return Pm1ConcentrationMeasurement[direction].attributes[key]
end
Pm1ConcentrationMeasurement.attributes = {}
setmetatable(Pm1ConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(Pm1ConcentrationMeasurement, {__index = cluster_base})

return Pm1ConcentrationMeasurement

