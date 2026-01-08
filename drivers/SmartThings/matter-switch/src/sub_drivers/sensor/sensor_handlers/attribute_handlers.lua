-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local version = require "version"
local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"
local fields = require "switch_utils.fields"
local sensor_fields = require "sub_drivers.sensor.switch_sensor_utils.fields"

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
    local temp = ib.data.value / 100.0
    local unit = "C"
    switch_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp)
    local min = switch_utils.get_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MIN, ib.endpoint_id)
    local max = switch_utils.get_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        switch_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MIN, ib.endpoint_id, nil)
        switch_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MAX, ib.endpoint_id, nil)
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


-- [[ BOOLEAN STATE CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.boolean_state_value_handler(driver, device, ib, response)
  if ib.data and ib.data.value then
    for device_type_id, _ in pairs(sensor_fields.BOOLEAN_STATE_CAPABILITY_MAP[ib.data.value] or {}) do
      local endpoint_ids = switch_utils.get_endpoints_by_device_type(device, device_type_id)
      if switch_utils.tbl_contains(endpoint_ids, ib.endpoint_id) then
        device:emit_event_for_endpoint(ib.endpoint_id, sensor_fields.BOOLEAN_STATE_CAPABILITY_MAP[ib.data.value][device_type_id])
      end
    end
  end
end


-- [[ BOOLEAN STATE CONFIGURATION CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.sensor_fault_handler(driver, device, ib, response)
  if ib.data.value > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.detected())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.clear())
  end
end

function SensorAttributeHandlers.supported_sensitivity_levels_handler(driver, device, ib, response)
  if ib.data.value then
    switch_utils.set_field_for_endpoint(device, fields.SUPPORTED_SENSITIVITY_LEVELS, ib.endpoint_id, ib.data.value, {persist = true})
  end
end

function SensorAttributeHandlers.boolean_state_configuration_attribute_list_handler(driver, device, ib, response)
  local clusters = require "st.matter.clusters"
  local cfg = require "switch_utils.device_configuration"
  local previous_sensor_fault_support = switch_utils.get_field(device, fields.profiling_data.SENSOR_FAULT_SUPPORTED)
  switch_utils.set_field(device, fields.profiling_data.SENSOR_FAULT_SUPPORTED, false, {persist=true})
  for _, attr in ipairs(ib.data.elements or {}) do
    if attr.value == clusters.BooleanStateConfiguration.attributes.SensorFault.ID then
      switch_utils.set_field(device, fields.profiling_data.SENSOR_FAULT_SUPPORTED, true, {persist=true})
      break
    end
  end
  if not previous_sensor_fault_support or previous_sensor_fault_support ~= switch_utils.get_field(device, fields.profiling_data.SENSOR_FAULT_SUPPORTED) then
    cfg.DeviceCfg.match_profile(driver, device)
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


-- [[ PRESSURE MEASUREMENT CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.pressure_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local kPa = st_utils.round(measured_value / 10.0)
    local unit = "kPa"
    device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({value = kPa, unit = unit}))
  end
end


-- [[ FLOW MEASUREMENT CLUSTER ATTRIBUTES ]] --

function SensorAttributeHandlers.flow_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local flow = measured_value / 10.0
    local unit = "m^3/h"
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.flowMeasurement.flow({value = flow, unit = unit}))
  end
end

function SensorAttributeHandlers.flow_measured_value_bounds_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local flow_bound = ib.data.value / 10.0
    local unit = "m^3/h"
    switch_utils.set_field_for_endpoint(device, sensor_fields.FLOW_BOUND_RECEIVED..minOrMax, ib.endpoint_id, flow_bound)
    local min = switch_utils.get_field_for_endpoint(device, sensor_fields.FLOW_BOUND_RECEIVED..sensor_fields.FLOW_MIN, ib.endpoint_id)
    local max = switch_utils.get_field_for_endpoint(device, sensor_fields.FLOW_BOUND_RECEIVED..sensor_fields.FLOW_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.flowMeasurement.flowRange({ value = { minimum = min, maximum = max }, unit = unit }))
        switch_utils.set_field_for_endpoint(device, sensor_fields.FLOW_BOUND_RECEIVED..sensor_fields.FLOW_MIN, ib.endpoint_id, nil)
        switch_utils.set_field_for_endpoint(device, sensor_fields.FLOW_BOUND_RECEIVED..sensor_fields.FLOW_MAX, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min flow measurement %d that is not lower than the reported max flow measurement %d", min, max))
      end
    end
  end
end

return SensorAttributeHandlers
