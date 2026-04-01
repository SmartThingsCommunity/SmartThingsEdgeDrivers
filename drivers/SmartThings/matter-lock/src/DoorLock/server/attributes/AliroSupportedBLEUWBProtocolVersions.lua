-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local AliroSupportedBLEUWBProtocolVersions = {
  ID = 0x0085,
  NAME = "AliroSupportedBLEUWBProtocolVersions",
  base_type = require "st.matter.data_types.Array",
  element_type = require "st.matter.data_types.OctetString1",
}

function AliroSupportedBLEUWBProtocolVersions:augment_type(data_type_obj)
  for i, v in ipairs(data_type_obj.elements) do
    data_type_obj.elements[i] = data_types.validate_or_build_type(v, AliroSupportedBLEUWBProtocolVersions.element_type)
  end
end

function AliroSupportedBLEUWBProtocolVersions:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function AliroSupportedBLEUWBProtocolVersions:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function AliroSupportedBLEUWBProtocolVersions:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function AliroSupportedBLEUWBProtocolVersions:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function AliroSupportedBLEUWBProtocolVersions:build_test_report_data(
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

function AliroSupportedBLEUWBProtocolVersions:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(AliroSupportedBLEUWBProtocolVersions, {__call = AliroSupportedBLEUWBProtocolVersions.new_value, __index = AliroSupportedBLEUWBProtocolVersions.base_type})
return AliroSupportedBLEUWBProtocolVersions
