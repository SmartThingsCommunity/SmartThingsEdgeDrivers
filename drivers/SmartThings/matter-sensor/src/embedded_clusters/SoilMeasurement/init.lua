local cluster_base = require "st.matter.cluster_base"
local SoilMeasurementServerAttributes = require "embedded_clusters.SoilMeasurement.server.attributes"

local SoilMeasurement = {}

SoilMeasurement.ID = 0x0430
SoilMeasurement.NAME = "SoilMeasurement"
SoilMeasurement.server = {}
SoilMeasurement.client = {}
SoilMeasurement.server.attributes = SoilMeasurementServerAttributes:set_parent_cluster(SoilMeasurement)

function SoilMeasurement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "SoilMoistureMeasurementLimits",
    [0x0001] = "SoilMoistureMeasuredValue",
    [0xFFF9] = "AcceptedCommandList",
    [0xFFFB] = "AttributeList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

SoilMeasurement.attribute_direction_map = {
  ["SoilMoistureMeasurementLimits"] = "server",
  ["SoilMoistureMeasuredValue"] = "server",
  ["AcceptedCommandList"] = "server",
  ["AttributeList"] = "server",
}

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = SoilMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, SoilMeasurement.NAME))
  end
  return SoilMeasurement[direction].attributes[key]
end
SoilMeasurement.attributes = {}
setmetatable(SoilMeasurement.attributes, attribute_helper_mt)

setmetatable(SoilMeasurement, {__index = cluster_base})

return SoilMeasurement
