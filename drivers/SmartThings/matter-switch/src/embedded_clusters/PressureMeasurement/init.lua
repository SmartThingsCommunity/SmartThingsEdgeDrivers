-- Copyright © 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local PressureMeasurementServerAttributes = require "embedded_clusters.PressureMeasurement.server.attributes"

local PressureMeasurement = {}

PressureMeasurement.ID = 0x0403
PressureMeasurement.NAME = "PressureMeasurement"
PressureMeasurement.server = {}
PressureMeasurement.client = {}
PressureMeasurement.server.attributes = PressureMeasurementServerAttributes:set_parent_cluster(PressureMeasurement)


function PressureMeasurement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "MeasuredValue",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

PressureMeasurement.attribute_direction_map = {
  ["MeasuredValue"] = "server",
}

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = PressureMeasurement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, PressureMeasurement.NAME))
  end
  return PressureMeasurement[direction].attributes[key]
end
PressureMeasurement.attributes = {}
setmetatable(PressureMeasurement.attributes, attribute_helper_mt)

setmetatable(PressureMeasurement, {__index = cluster_base})

return PressureMeasurement

