local cluster_base = require "st.matter.cluster_base"
local ElectricalPowerMeasurementServerAttributes = require "ElectricalPowerMeasurement.server.attributes"
local ElectricalPowerMeasurementTypes = require "ElectricalPowerMeasurement.types"

local ElectricalPowerMeasurement = {}

ElectricalPowerMeasurement.ID = 0x0090
ElectricalPowerMeasurement.NAME = "ElectricalPowerMeasurement"
ElectricalPowerMeasurement.server = {}
ElectricalPowerMeasurement.client = {}
ElectricalPowerMeasurement.server.attributes = ElectricalPowerMeasurementServerAttributes:set_parent_cluster(ElectricalPowerMeasurement)
ElectricalPowerMeasurement.types = ElectricalPowerMeasurementTypes

function ElectricalPowerMeasurement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "PowerMode",
    [0x0008] = "ActivePower",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

ElectricalPowerMeasurement.attribute_direction_map = {
  ["PowerMode"] = "server",
  ["ActivePower"] = "server",
}

ElectricalPowerMeasurement.FeatureMap = ElectricalPowerMeasurement.types.Feature

function ElectricalPowerMeasurement.are_features_supported(feature, feature_map)
  if (ElectricalPowerMeasurement.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ElectricalPowerMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ElectricalPowerMeasurement.NAME))
  end
  return ElectricalPowerMeasurement[direction].attributes[key]
end
ElectricalPowerMeasurement.attributes = {}
setmetatable(ElectricalPowerMeasurement.attributes, attribute_helper_mt)

setmetatable(ElectricalPowerMeasurement, {__index = cluster_base})

return ElectricalPowerMeasurement
