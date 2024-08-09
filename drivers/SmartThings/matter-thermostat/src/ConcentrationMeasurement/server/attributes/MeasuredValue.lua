local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local MeasuredValue = {
  ID = 0x0000,
  NAME = "MeasuredValue",
  base_type = require "st.matter.data_types.SinglePrecisionFloat",
}

function MeasuredValue:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function MeasuredValue:read(device, endpoint_id, cluster_id)
  return cluster_base.read(
    device,
    endpoint_id,
    cluster_id,
    self.ID,
    nil --event_id
  )
end


function MeasuredValue:subscribe(device, endpoint_id, cluster_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    cluster_id,
    self.ID,
    nil --event_id
  )
end

function MeasuredValue:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function MeasuredValue:build_test_report_data(
  device,
  endpoint_id,
  value,
  status,
  cluster_id
)
  local data = data_types.validate_or_build_type(value, self.base_type)

  return cluster_base.build_test_report_data(
    device,
    endpoint_id,
    cluster_id,
    self.ID,
    data,
    status
  )
end

function MeasuredValue:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(MeasuredValue, {__call = MeasuredValue.new_value, __index = MeasuredValue.base_type})
return MeasuredValue

