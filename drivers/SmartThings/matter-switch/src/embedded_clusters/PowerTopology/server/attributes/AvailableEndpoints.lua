local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local AvailableEndpoints = {
  ID = 0x0000,
  NAME = "AvailableEndpoints",
  base_type = require "st.matter.data_types.Array",
  element_type = require "st.matter.data_types.Uint16",
}

function AvailableEndpoints:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function AvailableEndpoints:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function AvailableEndpoints:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function AvailableEndpoints:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function AvailableEndpoints:build_test_report_data(
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

function AvailableEndpoints:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(AvailableEndpoints, {__call = AvailableEndpoints.new_value, __index = AvailableEndpoints.base_type})
return AvailableEndpoints

