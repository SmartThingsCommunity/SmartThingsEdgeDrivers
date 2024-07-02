local cluster_base = require "st.matter.cluster_base"
local OzoneConcentrationMeasurementServerAttributes = require "OzoneConcentrationMeasurement.server.attributes"
local ConcentrationMeasurement = require "ConcentrationMeasurement"

local OzoneConcentrationMeasurement = {}

OzoneConcentrationMeasurement.ID = 0x0415
OzoneConcentrationMeasurement.NAME = "OzoneConcentrationMeasurement"
OzoneConcentrationMeasurement.server = {}
OzoneConcentrationMeasurement.client = {}
OzoneConcentrationMeasurement.server.attributes = OzoneConcentrationMeasurementServerAttributes:set_parent_cluster(OzoneConcentrationMeasurement)
OzoneConcentrationMeasurement.types = ConcentrationMeasurement.types

function OzoneConcentrationMeasurement:get_attribute_by_id(attr_id)
  return ConcentrationMeasurement:get_attribute_by_id(attr_id)
end

function OzoneConcentrationMeasurement:get_server_command_by_id(command_id)
  return ConcentrationMeasurement:get_server_command_by_id(command_id)
end

OzoneConcentrationMeasurement.attribute_direction_map = ConcentrationMeasurement.attribute_direction_map

OzoneConcentrationMeasurement.FeatureMap = ConcentrationMeasurement.types.Feature

function OzoneConcentrationMeasurement.are_features_supported(feature, feature_map)
  return ConcentrationMeasurement.are_features_supported(feature, feature_map)
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = OzoneConcentrationMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, OzoneConcentrationMeasurement.NAME))
  end
  return OzoneConcentrationMeasurement[direction].attributes[key]
end
OzoneConcentrationMeasurement.attributes = {}
setmetatable(OzoneConcentrationMeasurement.attributes, attribute_helper_mt)

setmetatable(OzoneConcentrationMeasurement, {__index = cluster_base})

return OzoneConcentrationMeasurement

