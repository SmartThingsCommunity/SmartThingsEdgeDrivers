-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local PartsList = {
  ID = 0x0003,
  NAME = "PartsList",
  base_type = require "st.matter.data_types.Array",
  element_type = require "st.matter.data_types.Uint16",
}

function PartsList:augment_type(data_type_obj)
  for i, v in ipairs(data_type_obj.elements) do
    data_type_obj.elements[i] = data_types.validate_or_build_type(v, PartsList.element_type)
  end
end

function PartsList:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function PartsList:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function PartsList:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function PartsList:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function PartsList:build_test_report_data(
  device,
  endpoint_id,
  value,
  status
)
  local data = data_types.validate_or_build_type(value, self.base_type)

  return cluster_base.build_test_report_data(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    data,
    status
  )
end

function PartsList:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(PartsList, {__call = PartsList.new_value, __index = PartsList.base_type})
return PartsList

