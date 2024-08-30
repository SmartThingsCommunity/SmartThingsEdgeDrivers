local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local BatteryAlert = {
  ID = 0x0003,
  NAME = "BatteryAlert",
  base_type = require "SmokeCoAlarm.types.AlarmStateEnum",
}

function BatteryAlert:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function BatteryAlert:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end


function BatteryAlert:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function BatteryAlert:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function BatteryAlert:build_test_report_data(
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

function BatteryAlert:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(BatteryAlert, {__call = BatteryAlert.new_value, __index = BatteryAlert.base_type})
return BatteryAlert

