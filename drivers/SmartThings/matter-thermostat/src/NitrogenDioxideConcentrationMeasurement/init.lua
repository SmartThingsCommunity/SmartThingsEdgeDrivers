local cluster_base = require "st.matter.cluster_base"
local NitrogenDioxideConcentrationMeasurementServerAttributes = require "NitrogenDioxideConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local NitrogenDioxideConcentrationMeasurement = {}

NitrogenDioxideConcentrationMeasurement.ID = 0x0413
NitrogenDioxideConcentrationMeasurement.NAME = "NitrogenDioxideConcentrationMeasurement"
NitrogenDioxideConcentrationMeasurement.server = {}
NitrogenDioxideConcentrationMeasurement.client = {}
NitrogenDioxideConcentrationMeasurement.server.attributes = NitrogenDioxideConcentrationMeasurementServerAttributes:set_parent_cluster(NitrogenDioxideConcentrationMeasurement)
NitrogenDioxideConcentrationMeasurement.types = ConcentrationMeasurement.types

function NitrogenDioxideConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function NitrogenDioxideConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

NitrogenDioxideConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

NitrogenDioxideConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function NitrogenDioxideConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = NitrogenDioxideConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, NitrogenDioxideConcentrationMeasurement.NAME))
  end
  return NitrogenDioxideConcentrationMeasurement[direction].attributes[key]
end
NitrogenDioxideConcentrationMeasurement.attributes = {}
setmetatable(NitrogenDioxideConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(NitrogenDioxideConcentrationMeasurement, {__index = cluster_base})

return NitrogenDioxideConcentrationMeasurement

