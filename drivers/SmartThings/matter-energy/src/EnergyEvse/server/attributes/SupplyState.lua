local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local SupplyState = {
  ID = 0x0001,
  NAME = "SupplyState",
  base_type = data_types.Uint8,
}
SupplyState.DISABLED = 0x00
SupplyState.CHARGING_ENABLED = 0x01
SupplyState.DISCHARGING_ENABLED = 0x02
SupplyState.DISABLED_ERROR = 0x03
SupplyState.DISABLED_DIAGNOSTICS = 0x04

SupplyState.enum_fields = {
  [SupplyState.DISABLED] = "DISABLED",
  [SupplyState.CHARGING_ENABLED] = "CHARGING_ENABLED",
  [SupplyState.DISCHARGING_ENABLED] = "DISCHARGING_ENABLED",
  [SupplyState.DISABLED_ERROR] = "DISABLED_ERROR",
  [SupplyState.DISABLED_DIAGNOSTICS] = "DISABLED_DIAGNOSTICS",
}

function SupplyState:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function SupplyState.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, SupplyState.enum_fields[value_obj.value])
end

function SupplyState:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function SupplyState:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function SupplyState:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function SupplyState:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function SupplyState:build_test_report_data(
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

function SupplyState:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(SupplyState, {__call = SupplyState.new_value})
return SupplyState
