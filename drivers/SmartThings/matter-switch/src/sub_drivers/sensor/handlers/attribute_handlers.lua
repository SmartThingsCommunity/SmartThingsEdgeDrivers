-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"

local SensorAttributeHandlers = {}


-- [[ ILLUMINANCE CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.illuminance_measured_value_handler(driver, device, ib, response)
  local lux = math.floor(10 ^ ((ib.data.value - 1) / 10000))
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
end


-- [[ TEMPERATURE MEASUREMENT CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.temperature_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local temp = measured_value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
  end
end

function SensorAttributeHandlers.temperature_measured_value_bounds_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local sensor_fields = require "sub_drivers.sensor.utils.fields"
    local temp = ib.data.value / 100.0
    local unit = "C"
    switch_utils.set_field_for_endpoint(device, sensor_fields.TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp)
    local min = switch_utils.get_field_for_endpoint(device, sensor_fields.TEMP_BOUND_RECEIVED..sensor_fields.TEMP_MIN, ib.endpoint_id)
    local max = switch_utils.get_field_for_endpoint(device, sensor_fields.TEMP_BOUND_RECEIVED..sensor_fields.TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        local version = require "version"
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        switch_utils.set_field_for_endpoint(device, sensor_fields.TEMP_BOUND_RECEIVED..sensor_fields.TEMP_MIN, ib.endpoint_id, nil)
        switch_utils.set_field_for_endpoint(device, sensor_fields.TEMP_BOUND_RECEIVED..sensor_fields.TEMP_MAX, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end


-- [[ RELATIVE HUMIDITY MEASUREMENT CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.humidity_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local humidity = st_utils.round(measured_value / 100.0)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
  end
end


-- [[ OCCUPANCY SENSING CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.occupancy_measured_value_handler(driver, device, ib, response)
  if device:supports_capability(capabilities.motionSensor) then
    device:emit_event(ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
  else
    device:emit_event(ib.data.value == 0x01 and capabilities.presenceSensor.presence("present") or capabilities.presenceSensor.presence("not present"))
  end
end

return SensorAttributeHandlers
