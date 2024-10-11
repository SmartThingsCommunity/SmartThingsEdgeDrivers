local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local FaultState = {
  ID = 0x0002,
  NAME = "FaultState",
  base_type = data_types.Uint8,
}
FaultState.NO_ERROR = 0x00
FaultState.METER_FAILURE = 0x01
FaultState.OVER_VOLTAGE = 0x02
FaultState.UNDER_VOLTAGE = 0x03
FaultState.OVER_CURRENT = 0x04
FaultState.CONTACT_WET_FAILURE = 0x05
FaultState.CONTACT_DRY_FAILURE = 0x06
FaultState.GROUND_FAULT = 0x07
FaultState.POWER_LOSS = 0x08
FaultState.POWER_QUALITY = 0x09
FaultState.PILOT_SHORT_CIRCUIT = 0x0A
FaultState.EMERGENCY_STOP = 0x0B
FaultState.EV_DISCONNECTED = 0x0C
FaultState.WRONG_POWER_SUPPLY = 0x0D
FaultState.LIVE_NEUTRAL_SWAP = 0x0E
FaultState.OVER_TEMPERATURE = 0x0F
FaultState.OTHER = 0xFF

FaultState.enum_fields = {
  [FaultState.NO_ERROR] = "NO_ERROR",
  [FaultState.METER_FAILURE] = "METER_FAILURE",
  [FaultState.OVER_VOLTAGE] = "OVER_VOLTAGE",
  [FaultState.UNDER_VOLTAGE] = "UNDER_VOLTAGE",
  [FaultState.OVER_CURRENT] = "OVER_CURRENT",
  [FaultState.CONTACT_WET_FAILURE] = "CONTACT_WET_FAILURE",
  [FaultState.CONTACT_DRY_FAILURE] = "CONTACT_DRY_FAILURE",
  [FaultState.GROUND_FAULT] = "GROUND_FAULT",
  [FaultState.POWER_LOSS] = "POWER_LOSS",
  [FaultState.POWER_QUALITY] = "POWER_QUALITY",
  [FaultState.PILOT_SHORT_CIRCUIT] = "PILOT_SHORT_CIRCUIT",
  [FaultState.EMERGENCY_STOP] = "EMERGENCY_STOP",
  [FaultState.EV_DISCONNECTED] = "EV_DISCONNECTED",
  [FaultState.WRONG_POWER_SUPPLY] = "WRONG_POWER_SUPPLY",
  [FaultState.LIVE_NEUTRAL_SWAP] = "LIVE_NEUTRAL_SWAP",
  [FaultState.OVER_TEMPERATURE] = "OVER_TEMPERATURE",
  [FaultState.OTHER] = "OTHER",
}

function FaultState:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function FaultState.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, FaultState.enum_fields[value_obj.value])
end

function FaultState:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function FaultState:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function FaultState:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function FaultState:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function FaultState:build_test_report_data(
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

function FaultState:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(FaultState, {__call = FaultState.new_value})
return FaultState

