local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local SelectedWattIndex = {
  ID = 0x0007,
  NAME = "SelectedWattIndex",
  base_type = data_types.Uint8,
}

function SelectedWattIndex:new_value(...)
  local o = self.base_type(table.unpack({...}))
  
  return o
end

function SelectedWattIndex:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function SelectedWattIndex:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function SelectedWattIndex:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function SelectedWattIndex:build_test_report_data(
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

function SelectedWattIndex:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  
  return data
end

setmetatable(SelectedWattIndex, {__call = SelectedWattIndex.new_value})
return SelectedWattIndex
