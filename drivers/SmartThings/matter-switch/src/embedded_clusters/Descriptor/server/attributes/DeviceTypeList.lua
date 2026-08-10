-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local DeviceTypeList = {
  ID = 0x0000,
  NAME = "DeviceTypeList",
  base_type = require "st.matter.data_types.Array",
  element_type = require "embedded_clusters.Descriptor.types.DeviceTypeStruct",
}

function DeviceTypeList:augment_type(data_type_obj)
  for i, v in ipairs(data_type_obj.elements) do
    data_type_obj.elements[i] = data_types.validate_or_build_type(v, DeviceTypeList.element_type)
  end
end

function DeviceTypeList:new_value(...)
  local o = self.base_type(table.unpack({ ... }))
  return o
end

function DeviceTypeList:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function DeviceTypeList:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function DeviceTypeList:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function DeviceTypeList:build_test_report_data(
  device,
  endpoint_id,
  value,
  status
)
  local data = data_types.validate_or_build_type(value, self.base_type)
  self:augment_type(data)

  return cluster_base.build_test_report_data(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    data,
    status
  )
end

function DeviceTypeList:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(DeviceTypeList, { __call = DeviceTypeList.new_value, __index = DeviceTypeList.base_type })
return DeviceTypeList

