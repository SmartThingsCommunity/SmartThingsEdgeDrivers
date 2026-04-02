-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local st_utils = require "st.utils"
local sensor_utils = require "sensor_utils.utils"
local fields = require "sensor_utils.fields"
local device_cfg = require "sensor_utils.device_configuration"
local version = require "version"

local AttributeHandlers = {}


-- [[ ILLUMINANCE CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.illuminance_measured_value_handler(driver, device, ib, response)
  local lux = math.floor(10 ^ ((ib.data.value - 1) / 10000))
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
end


-- [[ TEMPERATURE MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.temperature_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local temp = measured_value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
  end
end

function AttributeHandlers.temperature_measured_value_bounds_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    sensor_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp)
    local min = sensor_utils.get_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MIN, ib.endpoint_id)
    local max = sensor_utils.get_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        sensor_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MIN, ib.endpoint_id, nil)
        sensor_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MAX, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end


-- [[ RELATIVE HUMIDITY MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.humidity_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local humidity = st_utils.round(measured_value / 100.0)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
  end
end


-- [[ BOOLEAN STATE CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.boolean_state_value_handler(driver, device, ib, response)
  local name
  for dt_name, _ in pairs(fields.BOOLEAN_DEVICE_TYPE_INFO) do
      local dt_ep_id = device:get_field(dt_name)
      if ib.endpoint_id == dt_ep_id then
          name = dt_name
          break
      end
  end
  if name then
    device:emit_event_for_endpoint(ib.endpoint_id, fields.BOOLEAN_CAP_EVENT_MAP[ib.data.value][name])
  elseif device:supports_capability(capabilities.contactSensor) then
    -- The generic case where no device type has been specified but the profile uses this capability.
      device:emit_event_for_endpoint(ib.endpoint_id, fields.BOOLEAN_CAP_EVENT_MAP[ib.data.value]["CONTACT_SENSOR"])
  else
    device.log.error("No Boolean device type found on an endpoint, BooleanState handler aborted")
  end
end


-- [[ BOOLEAN STATE CONFIGURATION CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.sensor_fault_handler(driver, device, ib, response)
  if ib.data.value > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.detected())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.clear())
  end
end

function AttributeHandlers.supported_sensitivity_levels_handler(driver, device, ib, response)
  if ib.data.value then
    for dt_name, info in pairs(fields.BOOLEAN_DEVICE_TYPE_INFO) do
      if device:get_field(dt_name) == ib.endpoint_id then
        device:set_field(info.sensitivity_max, ib.data.value, {persist = true})
      end
    end
  end
end


-- [[ POWER SOURCE CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.bat_percent_remaining_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

function AttributeHandlers.bat_charge_level_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

function AttributeHandlers.power_source_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      device_cfg.match_profile(driver, device, fields.battery_support.BATTERY_PERCENTAGE)
      return
    elseif attr.value == 0x0E then
      device_cfg.match_profile(driver, device, fields.battery_support.BATTERY_LEVEL)
      return
    end
  end
end


-- [[ OCCUPANCY SENSING CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.occupancy_measured_value_handler(driver, device, ib, response)
  if device:supports_capability(capabilities.motionSensor) then
    device:emit_event(ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
  else
    device:emit_event(ib.data.value == 0x01 and capabilities.presenceSensor.presence("present") or capabilities.presenceSensor.presence("not present"))
  end
end


-- [[ PRESSURE MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.pressure_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local kPa = st_utils.round(measured_value / 10.0)
    local unit = "kPa"
    device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({value = kPa, unit = unit}))
  end
end


-- [[ FLOW MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.flow_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local flow = measured_value / 10.0
    local unit = "m^3/h"
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.flowMeasurement.flow({value = flow, unit = unit}))
  end
end

function AttributeHandlers.flow_measured_value_bounds_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local flow_bound = ib.data.value / 10.0
    local unit = "m^3/h"
    sensor_utils.set_field_for_endpoint(device, fields.FLOW_BOUND_RECEIVED..minOrMax, ib.endpoint_id, flow_bound)
    local min = sensor_utils.get_field_for_endpoint(device, fields.FLOW_BOUND_RECEIVED..fields.FLOW_MIN, ib.endpoint_id)
    local max = sensor_utils.get_field_for_endpoint(device, fields.FLOW_BOUND_RECEIVED..fields.FLOW_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.flowMeasurement.flowRange({ value = { minimum = min, maximum = max }, unit = unit }))
        sensor_utils.set_field_for_endpoint(device, fields.FLOW_BOUND_RECEIVED..fields.FLOW_MIN, ib.endpoint_id, nil)
        sensor_utils.set_field_for_endpoint(device, fields.FLOW_BOUND_RECEIVED..fields.FLOW_MAX, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min flow measurement %d that is not lower than the reported max flow measurement %d", min, max))
      end
    end
  end
end

return AttributeHandlers