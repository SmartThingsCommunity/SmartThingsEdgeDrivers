local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local CountdownTime = {
  ID = 0x0002,
  NAME = "CountdownTime",
  base_type = require "st.matter.data_types.Uint32",
}

function CountdownTime:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function CountdownTime:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function CountdownTime:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function CountdownTime:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function CountdownTime:build_test_report_data(
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

function CountdownTime:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(CountdownTime, {__call = CountdownTime.new_value, __index = CountdownTime.base_type})
return CountdownTime
