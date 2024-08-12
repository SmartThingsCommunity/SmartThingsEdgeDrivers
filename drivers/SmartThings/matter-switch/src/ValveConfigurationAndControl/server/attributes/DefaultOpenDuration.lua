local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local DefaultOpenDuration = {
  ID = 0x0001,
  NAME = "DefaultOpenDuration",
  base_type = require "st.matter.data_types.Uint32",
}

function DefaultOpenDuration:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function DefaultOpenDuration:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function DefaultOpenDuration:write(device, endpoint_id, value)
  local data = data_types.validate_or_build_type(value, self.base_type)

  return cluster_base.write(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil,
    data
  )
end

function DefaultOpenDuration:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function DefaultOpenDuration:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function DefaultOpenDuration:build_test_report_data(
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

function DefaultOpenDuration:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(DefaultOpenDuration, {__call = DefaultOpenDuration.new_value, __index = DefaultOpenDuration.base_type})
return DefaultOpenDuration
