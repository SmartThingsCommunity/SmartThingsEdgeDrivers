local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local EffectiveOperationMode = {
  ID = 0x0011,
  NAME = "EffectiveOperationMode",
  base_type = require "PumpConfigurationAndControl.types.OperationModeEnum",
}

function EffectiveOperationMode:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function EffectiveOperationMode:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function EffectiveOperationMode:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function EffectiveOperationMode:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function EffectiveOperationMode:build_test_report_data(
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

function EffectiveOperationMode:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(EffectiveOperationMode, {__call = EffectiveOperationMode.new_value, __index = EffectiveOperationMode.base_type})
return EffectiveOperationMode
