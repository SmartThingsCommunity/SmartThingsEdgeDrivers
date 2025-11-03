local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local MeasurementUnit = {
  ID = 0x0008,
  NAME = "MeasurementUnit",
  base_type = require "ConcentrationMeasurement.types.MeasurementUnitEnum",
}

function MeasurementUnit:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function MeasurementUnit:read(device, endpoint_id, cluster_id)
  return cluster_base.read(
    device,
    endpoint_id,
    cluster_id,
    self.ID,
    nil --event_id
  )
end

function MeasurementUnit:subscribe(device, endpoint_id, cluster_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    cluster_id,
    self.ID,
    nil --event_id
  )
end

function MeasurementUnit:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function MeasurementUnit:build_test_report_data(
  device,
  endpoint_id,
  value,
  status,
  cluster_id
)
  local data = data_types.validate_or_build_type(value, self.base_type)
  self:augment_type(data)
  return cluster_base.build_test_report_data(
    device,
    endpoint_id,
    cluster_id,
    self.ID,
    data,
    status
  )
end

function MeasurementUnit:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(MeasurementUnit, {__call = MeasurementUnit.new_value, __index = MeasurementUnit.base_type})
return MeasurementUnit

