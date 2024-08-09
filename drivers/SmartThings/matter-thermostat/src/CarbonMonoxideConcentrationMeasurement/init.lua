local cluster_base = require "st.matter.cluster_base"
local CarbonMonoxideConcentrationMeasurementServerAttributes = require "CarbonMonoxideConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local CarbonMonoxideConcentrationMeasurement = {}

CarbonMonoxideConcentrationMeasurement.ID = 0x040C
CarbonMonoxideConcentrationMeasurement.NAME = "CarbonMonoxideConcentrationMeasurement"
CarbonMonoxideConcentrationMeasurement.server = {}
CarbonMonoxideConcentrationMeasurement.client = {}
CarbonMonoxideConcentrationMeasurement.server.attributes = CarbonMonoxideConcentrationMeasurementServerAttributes:set_parent_cluster(CarbonMonoxideConcentrationMeasurement)
CarbonMonoxideConcentrationMeasurement.types = ConcentrationMeasurement.types

function CarbonMonoxideConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function CarbonMonoxideConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

CarbonMonoxideConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

CarbonMonoxideConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function CarbonMonoxideConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = CarbonMonoxideConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, CarbonMonoxideConcentrationMeasurement.NAME))
  end
  return CarbonMonoxideConcentrationMeasurement[direction].attributes[key]
end
CarbonMonoxideConcentrationMeasurement.attributes = {}
setmetatable(CarbonMonoxideConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(CarbonMonoxideConcentrationMeasurement, {__index = cluster_base})

return CarbonMonoxideConcentrationMeasurement

