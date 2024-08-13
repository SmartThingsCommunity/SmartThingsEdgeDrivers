local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local RemainingDuration = {
  ID = 0x0003,
  NAME = "RemainingDuration",
  base_type = require "st.matter.data_types.Uint32",
}

function RemainingDuration:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function RemainingDuration:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function RemainingDuration:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function RemainingDuration:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function RemainingDuration:build_test_report_data(
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

function RemainingDuration:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(RemainingDuration, {__call = RemainingDuration.new_value, __index = RemainingDuration.base_type})
return RemainingDuration
