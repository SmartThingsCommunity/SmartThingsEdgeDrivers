local ConcentrationMeasurementServerAttributesLevelValue = require "ConcentrationMeasurement.server.attributes.LevelValue"

local LevelValue = {
  ID = 0x000A,
  NAME = "LevelValue",
  base_type = require "ConcentrationMeasurement.types.LevelValueEnum",
}

function LevelValue:new_value(...)
  ConcentrationMeasurementServerAttributesLevelValue:new_value(...)
end

function LevelValue:read(device, endpoint_id)
  return ConcentrationMeasurementServerAttributesLevelValue:read(device, endpoint_id, self._cluster.ID)
end

function LevelValue:subscribe(device, endpoint_id)
  return ConcentrationMeasurementServerAttributesLevelValue:subscribe(device, endpoint_id, self._cluster.ID)
end

function LevelValue:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function LevelValue:build_test_report_data(
  device,
  endpoint_id,
  value,
  status
)
  return ConcentrationMeasurementServerAttributesLevelValue:build_test_report_data(device, endpoint_id, value, status, self._cluster.ID)
end

function LevelValue:deserialize(tlv_buf)
  return ConcentrationMeasurementServerAttributesLevelValue:deserialize(tlv_buf)
end

setmetatable(LevelValue, {__call = LevelValue.new_value, __index = LevelValue.base_type})
return LevelValue

