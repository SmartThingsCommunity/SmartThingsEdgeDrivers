-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"

local AirQualityServerAttributeHandlers = {}


-- [[ GENERIC CONCENTRATION MEASUREMENT CLUSTER ATTRIBUTES ]]

function AirQualityServerAttributeHandlers.measurement_unit_factory(capability_name)
  return function(driver, device, ib, response)
    device:set_field(capability_name.."_unit", ib.data.value, {persist = true})
  end
end

function AirQualityServerAttributeHandlers.level_value_factory(attribute)
  return function(driver, device, ib, response)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(fields.level_strings[ib.data.value]))
  end
end

local function unit_conversion(device, value, from_unit, to_unit)
  local conversion_function = fields.conversion_tables[from_unit][to_unit]
  if conversion_function == nil then
    device.log.info_with( {hub_logs = true} , string.format("Unsupported unit conversion from %s to %s", fields.unit_strings[from_unit], fields.unit_strings[to_unit]))
    return 1
  end

  if value == nil then
    device.log.info_with( {hub_logs = true} , "unit conversion value is nil")
    return 1
  end
  return conversion_function(value)
end

function AirQualityServerAttributeHandlers.measured_value_factory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    local reporting_unit = device:get_field(capability_name.."_unit")

    if reporting_unit == nil then
      reporting_unit = fields.unit_default[capability_name]
      device:set_field(capability_name.."_unit", reporting_unit, {persist = true})
    end

    if reporting_unit then
      local value = unit_conversion(device, ib.data.value, reporting_unit, target_unit)
      device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = value, unit = fields.unit_strings[target_unit]}))

      -- handle case where device profile supports both fineDustLevel and dustLevel
      if capability_name == capabilities.fineDustSensor.NAME and device:supports_capability(capabilities.dustSensor) then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.dustSensor.fineDustLevel({value = value, unit = fields.unit_strings[target_unit]}))
      end
    end
  end
end


-- [[ AIR QUALITY CLUSTER ATTRIBUTES ]] --

function AirQualityServerAttributeHandlers.air_quality_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Unknown
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.unknown())
  elseif state == 1 then -- Good
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.good())
  elseif state == 2 then -- Fair
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.moderate())
  elseif state == 3 then -- Moderate
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.slightlyUnhealthy())
  elseif state == 4 then -- Poor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.unhealthy())
  elseif state == 5 then -- VeryPoor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.veryUnhealthy())
  elseif state == 6 then -- ExtremelyPoor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.hazardous())
  end
end


-- [[ PRESSURE MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AirQualityServerAttributeHandlers.pressure_measured_value_handler(driver, device, ib, response)
  local pressure = st_utils.round(ib.data.value / 10.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.atmosphericPressureMeasurement.atmosphericPressure(pressure))
end

return AirQualityServerAttributeHandlers
