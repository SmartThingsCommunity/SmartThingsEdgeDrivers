-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local SoilMeasurementServerAttributes = require "embedded_clusters.SoilMeasurement.server.attributes"
local SoilMeasurementTypes = require "embedded_clusters.SoilMeasurement.types"

--- @class SoilMeasurement
--- @alias SoilMeasurement
---
--- @field public ID number 0x0430 the ID of this cluster
--- @field public NAME string "SoilMeasurement" the name of this cluster
--- @field public attributes SoilMeasurementServerAttributes
--- @field public types SoilMeasurementTypes

local SoilMeasurement = {}

SoilMeasurement.ID = 0x0430
SoilMeasurement.NAME = "SoilMeasurement"
SoilMeasurement.server = {}
SoilMeasurement.client = {}
SoilMeasurement.server.attributes = SoilMeasurementServerAttributes:set_parent_cluster(SoilMeasurement)
SoilMeasurement.types = SoilMeasurementTypes


--- Find an attribute by id
---
--- @param attr_id number
function SoilMeasurement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "SoilMoistureMeasurementLimits",
    [0x0001] = "SoilMoistureMeasuredValue",
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
}

--- @class SoilMeasurement.InteractionResponse
--- @field public ID number 0x0430 the ID of this cluster
--- @field public NAME string "SoilMeasurement" the name of this cluster
--- @field public body table the body of the interaction response
SoilMeasurement.InteractionResponse = {}

function SoilMeasurement.InteractionResponse:set_field_names()
  self.field_names = {
  }
end

function SoilMeasurement:init(...)
  self.InteractionResponse:set_field_names()
end

function SoilMeasurement:augment_type(base_type_obj)
  base_type_obj.field_defs = {}
  base_type_obj.field_names = {}
end

setmetatable(SoilMeasurement, {__call = SoilMeasurement.init})

return SoilMeasurement
