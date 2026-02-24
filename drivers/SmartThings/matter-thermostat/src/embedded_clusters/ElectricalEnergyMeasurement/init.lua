-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local ElectricalEnergyMeasurementServerAttributes = require "embedded_clusters.ElectricalEnergyMeasurement.server.attributes"
local ElectricalEnergyMeasurementTypes = require "embedded_clusters.ElectricalEnergyMeasurement.types"
local ElectricalEnergyMeasurement = {}

ElectricalEnergyMeasurement.ID = 0x0091
ElectricalEnergyMeasurement.NAME = "ElectricalEnergyMeasurement"
ElectricalEnergyMeasurement.server = {}
ElectricalEnergyMeasurement.client = {}
ElectricalEnergyMeasurement.server.attributes = ElectricalEnergyMeasurementServerAttributes:set_parent_cluster(ElectricalEnergyMeasurement)
ElectricalEnergyMeasurement.types = ElectricalEnergyMeasurementTypes

function ElectricalEnergyMeasurement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0001] = "CumulativeEnergyImported",
    [0x0003] = "PeriodicEnergyImported",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

ElectricalEnergyMeasurement.attribute_direction_map = {
  ["CumulativeEnergyImported"] = "server",
  ["PeriodicEnergyImported"] = "server",
}

ElectricalEnergyMeasurement.FeatureMap = ElectricalEnergyMeasurement.types.Feature

function ElectricalEnergyMeasurement.are_features_supported(feature, feature_map)
  if (ElectricalEnergyMeasurement.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ElectricalEnergyMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ElectricalEnergyMeasurement.NAME))
  end
  return ElectricalEnergyMeasurement[direction].attributes[key]
end
ElectricalEnergyMeasurement.attributes = {}
setmetatable(ElectricalEnergyMeasurement.attributes, attribute_helper_mt)

setmetatable(ElectricalEnergyMeasurement, {__index = cluster_base})

return ElectricalEnergyMeasurement

