local TLVParser = require "st.matter.TLV.TLVParser"
local ConcentrationMeasurementServerAttributesMeasurementUnit = require "ConcentrationMeasurement.server.attributes.MeasurementUnit"


local MeasurementUnit = {
  ID = 0x0008,
  NAME = "MeasurementUnit",
  base_type = require "ConcentrationMeasurement.types.MeasurementUnitEnum",
}

function MeasurementUnit:new_value(...)
  return ConcentrationMeasurementServerAttributesMeasurementUnit:new_value(...)
end

function MeasurementUnit:read(device, endpoint_id)
  return ConcentrationMeasurementServerAttributesMeasurementUnit:read(device, endpoint_id, self._cluster.ID)
end

function MeasurementUnit:subscribe(device, endpoint_id)
  return ConcentrationMeasurementServerAttributesMeasurementUnit:subscribe(device, endpoint_id, self._cluster.ID)
end

function MeasurementUnit:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function MeasurementUnit:build_test_report_data(
  device,
  endpoint_id,
  value,
  status
)
  return ConcentrationMeasurementServerAttributesMeasurementUnit:build_test_report_data(device, endpoint_id, value, status, self._cluster.ID)
end

function MeasurementUnit:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(MeasurementUnit, {__call = MeasurementUnit.new_value, __index = MeasurementUnit.base_type})
return MeasurementUnit

