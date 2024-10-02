local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local ApproximateEVEfficiency = {
  ID = 0x0027,
  NAME = "ApproximateEVEfficiency",
  base_type = data_types.Uint16,
}

function ApproximateEVEfficiency:new_value(...)
  local o = self.base_type(table.unpack({...}))
  return o
end

function ApproximateEVEfficiency:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function ApproximateEVEfficiency:write(device, endpoint_id, value)
  local data = data_types.validate_or_build_type(value, self.base_type)
  return cluster_base.write(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil, --event_id
    data
  )
end

function ApproximateEVEfficiency:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function ApproximateEVEfficiency:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function ApproximateEVEfficiency:build_test_report_data(
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

function ApproximateEVEfficiency:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  return data
end

setmetatable(ApproximateEVEfficiency, {__call = ApproximateEVEfficiency.new_value})
return ApproximateEVEfficiency