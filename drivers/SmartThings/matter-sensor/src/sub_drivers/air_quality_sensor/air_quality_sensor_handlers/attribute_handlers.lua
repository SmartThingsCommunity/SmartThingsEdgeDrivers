-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local aqs_fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"

local AirQualitySensorAttributeHandlers = {}


-- [[ GENERIC CONCENTRATION MEASUREMENT CLUSTER ATTRIBUTES ]]

function AirQualitySensorAttributeHandlers.measurement_unit_factory(capability_name)
  return function(driver, device, ib, response)
    device:set_field(capability_name.."_unit", ib.data.value, {persist = true})
  end
end

function AirQualitySensorAttributeHandlers.level_value_factory(attribute)
  return function(driver, device, ib, response)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(aqs_fields.level_strings[ib.data.value]))
  end
end

function AirQualitySensorAttributeHandlers.measured_value_factory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    if ib.data.value then
      local reporting_unit = device:get_field(capability_name.."_unit") or aqs_fields.unit_default[capability_name]
      local conversion_function = aqs_fields.conversion_tables[reporting_unit][target_unit]
      if conversion_function then
        local converted_value = conversion_function(ib.data.value)
        device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = converted_value, unit = aqs_fields.unit_strings[target_unit]}))
        -- handle case where device profile supports both fineDustLevel and dustLevel
        if capability_name == capabilities.fineDustSensor.NAME and device:supports_capability(capabilities.dustSensor) then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.dustSensor.fineDustLevel({value = converted_value, unit = aqs_fields.unit_strings[target_unit]}))
        end
      else
        device.log.info_with({hub_logs=true}, string.format("Unsupported unit conversion from %s to %s", aqs_fields.unit_strings[reporting_unit], aqs_fields.unit_strings[target_unit]))
      end
    end
  end
end


-- [[ AIR QUALITY CLUSTER ATTRIBUTES ]] --

function AirQualitySensorAttributeHandlers.air_quality_handler(driver, device, ib, response)
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

function AirQualitySensorAttributeHandlers.pressure_measured_value_handler(driver, device, ib, response)
  local pressure = st_utils.round(ib.data.value / 10.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.atmosphericPressureMeasurement.atmosphericPressure(pressure))
end

return AirQualitySensorAttributeHandlers
