local cluster_base = require "st.matter.cluster_base"
local CarbonDioxideConcentrationMeasurementServerAttributes = require "CarbonDioxideConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local CarbonDioxideConcentrationMeasurement = {}

CarbonDioxideConcentrationMeasurement.ID = 0x040D
CarbonDioxideConcentrationMeasurement.NAME = "CarbonDioxideConcentrationMeasurement"
CarbonDioxideConcentrationMeasurement.server = {}
CarbonDioxideConcentrationMeasurement.client = {}
CarbonDioxideConcentrationMeasurement.server.attributes = CarbonDioxideConcentrationMeasurementServerAttributes:set_parent_cluster(CarbonDioxideConcentrationMeasurement)
CarbonDioxideConcentrationMeasurement.types = ConcentrationMeasurement.types

function CarbonDioxideConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function CarbonDioxideConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

CarbonDioxideConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

CarbonDioxideConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function CarbonDioxideConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = CarbonDioxideConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, CarbonDioxideConcentrationMeasurement.NAME))
  end
  return CarbonDioxideConcentrationMeasurement[direction].attributes[key]
end
CarbonDioxideConcentrationMeasurement.attributes = {}
setmetatable(CarbonDioxideConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(CarbonDioxideConcentrationMeasurement, {__index = cluster_base})

return CarbonDioxideConcentrationMeasurement

