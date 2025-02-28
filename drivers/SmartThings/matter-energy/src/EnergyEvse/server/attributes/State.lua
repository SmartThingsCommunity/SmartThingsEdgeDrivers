local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local State = {
  ID = 0x0000,
  NAME = "State",
  base_type = data_types.Uint8,
}
State.NOT_PLUGGED_IN = 0x00
State.PLUGGED_IN_NO_DEMAND = 0x01
State.PLUGGED_IN_DEMAND = 0x02
State.PLUGGED_IN_CHARGING = 0x03
State.PLUGGED_IN_DISCHARGING = 0x04
State.SESSION_ENDING = 0x05
State.FAULT = 0x06

State.enum_fields = {
  [State.NOT_PLUGGED_IN] = "NOT_PLUGGED_IN",
  [State.PLUGGED_IN_NO_DEMAND] = "PLUGGED_IN_NO_DEMAND",
  [State.PLUGGED_IN_DEMAND] = "PLUGGED_IN_DEMAND",
  [State.PLUGGED_IN_CHARGING] = "PLUGGED_IN_CHARGING",
  [State.PLUGGED_IN_DISCHARGING] = "PLUGGED_IN_DISCHARGING",
  [State.SESSION_ENDING] = "SESSION_ENDING",
  [State.FAULT] = "FAULT",
}

function State:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function State.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, State.enum_fields[value_obj.value])
end

function State:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function State:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function State:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function State:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function State:build_test_report_data(
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

function State:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(State, {__call = State.new_value})
return State
