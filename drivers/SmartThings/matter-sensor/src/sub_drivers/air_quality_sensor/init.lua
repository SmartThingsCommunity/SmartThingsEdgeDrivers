-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local version = require "version"
local log = require "log"

local fields = require "sub_drivers.air_quality_sensor.fields"
local match_modular_profile = require "sub_drivers.air_quality_sensor.modular_configuration"
local match_profile_static = require "sub_drivers.air_quality_sensor.static_configuration"

-- Include driver-side definitions when lua libs api version is < 10
if version.api < 10 then
  clusters.AirQuality = require "embedded_clusters.AirQuality"
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.CarbonDioxideConcentrationMeasurement = require "embedded_clusters.CarbonDioxideConcentrationMeasurement"
  clusters.FormaldehydeConcentrationMeasurement = require "embedded_clusters.FormaldehydeConcentrationMeasurement"
  clusters.NitrogenDioxideConcentrationMeasurement = require "embedded_clusters.NitrogenDioxideConcentrationMeasurement"
  clusters.OzoneConcentrationMeasurement = require "embedded_clusters.OzoneConcentrationMeasurement"
  clusters.Pm1ConcentrationMeasurement = require "embedded_clusters.Pm1ConcentrationMeasurement"
  clusters.Pm10ConcentrationMeasurement = require "embedded_clusters.Pm10ConcentrationMeasurement"
  clusters.Pm25ConcentrationMeasurement = require "embedded_clusters.Pm25ConcentrationMeasurement"
  clusters.RadonConcentrationMeasurement = require "embedded_clusters.RadonConcentrationMeasurement"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "embedded_clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement"
end


-- SUBDRIVER UTILS --

local air_quality_sensor_utils = {}

function air_quality_sensor_utils.is_matter_air_quality_sensor(opts, driver, device)
    for _, ep in ipairs(device.endpoints) do
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == fields.AIR_QUALITY_SENSOR_DEVICE_TYPE_ID then
          return true
        end
      end
    end

    return false
  end

function air_quality_sensor_utils.supports_capability_by_id_modular(device, capability, component)
  if not device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) then
    device.log.warn_with({hub_logs = true}, "Device has overriden supports_capability_by_id, but does not have supported capabilities set.")
    return false
  end
  for _, component_capabilities in ipairs(device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES)) do
    local comp_id = component_capabilities[1]
    local capability_ids = component_capabilities[2]
    if (component == nil) or (component == comp_id) then
        for _, cap in ipairs(capability_ids) do
          if cap == capability then
            return true
          end
        end
    end
  end
  return false
end


-- AIR QUALITY SENSOR LIFECYCLE HANDLERS --

local AirQualitySensorLifecycleHandlers = {}

function AirQualitySensorLifecycleHandlers.do_configure(driver, device)
  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(fields.units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end
  if version.api >= 14 and version.rpc >= 8 then
    match_modular_profile(device)
  else
    match_profile_static(device)
  end
end

function AirQualitySensorLifecycleHandlers.driver_switched(driver, device)
  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(fields.units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end
  if version.api >= 14 and version.rpc >= 8 then
    match_modular_profile(device)
  else
    match_profile_static(device)
  end
end

function AirQualitySensorLifecycleHandlers.device_init(driver, device)
  if device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) and (version.api < 15 or version.rpc < 9) then
    -- assume that device is using a modular profile on 0.57 FW, override supports_capability_by_id
    -- library function to utilize optional capabilities
    device:extend_device("supports_capability_by_id", air_quality_sensor_utils.supports_capability_by_id_modular)
  end
  device:subscribe()
end

function AirQualitySensorLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    if device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) then
      --re-up subscription with new capabilities using the modular supports_capability override
       device:extend_device("supports_capability_by_id", air_quality_sensor_utils.supports_capability_by_id_modular)
    end
    device:subscribe()
  end
end

-- ATTRIBUTE HANDLERS --

local sub_driver_handlers = {}

function sub_driver_handlers.measurement_unit_factory(capability_name)
  return function(driver, device, ib, response)
    device:set_field(capability_name.."_unit", ib.data.value, {persist = true})
  end
end

local function unit_conversion(value, from_unit, to_unit)
  local conversion_function = fields.conversion_tables[from_unit][to_unit]
  if conversion_function == nil then
    log.info_with( {hub_logs = true} , string.format("Unsupported unit conversion from %s to %s", fields.unit_strings[from_unit], fields.unit_strings[to_unit]))
    return 1
  end

  if value == nil then
    log.info_with( {hub_logs = true} , "unit conversion value is nil")
    return 1
  end
  return conversion_function(value)
end

function sub_driver_handlers.measured_value_factory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    local reporting_unit = device:get_field(capability_name.."_unit")

    if reporting_unit == nil then
      reporting_unit = fields.unit_default[capability_name]
      device:set_field(capability_name.."_unit", reporting_unit, {persist = true})
    end

    if reporting_unit then
      local value = unit_conversion(ib.data.value, reporting_unit, target_unit)
      device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = value, unit = fields.unit_strings[target_unit]}))

      -- handle case where device profile supports both fineDustLevel and dustLevel
      if capability_name == capabilities.fineDustSensor.NAME and device:supports_capability(capabilities.dustSensor) then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.dustSensor.fineDustLevel({value = value, unit = fields.unit_strings[target_unit]}))
      end
    end
  end
end

function sub_driver_handlers.level_value_factory(attribute)
  return function(driver, device, ib, response)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(fields.level_strings[ib.data.value]))
  end
end

function sub_driver_handlers.air_quality_handler(driver, device, ib, response)
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

function sub_driver_handlers.pressure_measured_value_handler(driver, device, ib, response)
  local pressure = utils.round(ib.data.value / 10.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.atmosphericPressureMeasurement.atmosphericPressure(pressure))
end


-- SUBDRIVER TEMPLATE --

local matter_air_quality_sensor_handler = {
  NAME = "matter-air-quality-sensor",
  lifecycle_handlers = {
    doConfigure = AirQualitySensorLifecycleHandlers.do_configure,
    driverSwitched = AirQualitySensorLifecycleHandlers.driver_switched,
    infoChanged = AirQualitySensorLifecycleHandlers.info_changed,
    init = AirQualitySensorLifecycleHandlers.device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.AirQuality.ID] = {
        [clusters.AirQuality.attributes.AirQuality.ID] = sub_driver_handlers.air_quality_handler,
      },
      [clusters.CarbonDioxideConcentrationMeasurement.ID] = {
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.carbonDioxideMeasurement.NAME, capabilities.carbonDioxideMeasurement.carbonDioxide, fields.units.PPM),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.carbonDioxideMeasurement.NAME),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern),
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.carbonMonoxideMeasurement.NAME, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel, fields.units.PPM),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.carbonMonoxideMeasurement.NAME),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.carbonMonoxideHealthConcern.carbonMonoxideHealthConcern),
      },
      [clusters.FormaldehydeConcentrationMeasurement.ID] = {
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.formaldehydeMeasurement.NAME, capabilities.formaldehydeMeasurement.formaldehydeLevel, fields.units.PPM),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.formaldehydeMeasurement.NAME),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.formaldehydeHealthConcern.formaldehydeHealthConcern),
      },
      [clusters.NitrogenDioxideConcentrationMeasurement.ID] = {
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.nitrogenDioxideMeasurement.NAME, capabilities.nitrogenDioxideMeasurement.nitrogenDioxide, fields.units.PPM),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.nitrogenDioxideMeasurement.NAME),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.nitrogenDioxideHealthConcern.nitrogenDioxideHealthConcern)
      },
      [clusters.OzoneConcentrationMeasurement.ID] = {
        [clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.ozoneMeasurement.NAME, capabilities.ozoneMeasurement.ozone, fields.units.PPM),
        [clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.ozoneMeasurement.NAME),
        [clusters.OzoneConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.ozoneHealthConcern.ozoneHealthConcern)
      },
      [clusters.Pm1ConcentrationMeasurement.ID] = {
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.veryFineDustSensor.NAME, capabilities.veryFineDustSensor.veryFineDustLevel, fields.units.UGM3),
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.veryFineDustSensor.NAME),
        [clusters.Pm1ConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern),
      },
      [clusters.Pm10ConcentrationMeasurement.ID] = {
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.dustSensor.NAME, capabilities.dustSensor.dustLevel, fields.units.UGM3),
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.dustSensor.NAME),
        [clusters.Pm10ConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.dustHealthConcern.dustHealthConcern),
      },
      [clusters.Pm25ConcentrationMeasurement.ID] = {
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.fineDustSensor.NAME, capabilities.fineDustSensor.fineDustLevel, fields.units.UGM3),
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.fineDustSensor.NAME),
        [clusters.Pm25ConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.fineDustHealthConcern.fineDustHealthConcern),
      },
      [clusters.PressureMeasurement.ID] = {
        [clusters.PressureMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.pressure_measured_value_handler
      },
      [clusters.RadonConcentrationMeasurement.ID] = {
        [clusters.RadonConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.radonMeasurement.NAME, capabilities.radonMeasurement.radonLevel, fields.units.PCIL),
        [clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.radonMeasurement.NAME),
        [clusters.RadonConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.radonHealthConcern.radonHealthConcern)
      },
      [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID] = {
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.measured_value_factory(capabilities.tvocMeasurement.NAME, capabilities.tvocMeasurement.tvocLevel, fields.units.PPB),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.measurement_unit_factory(capabilities.tvocMeasurement.NAME),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue.ID] = sub_driver_handlers.level_value_factory(capabilities.tvocHealthConcern.tvocHealthConcern)
      }
    }
  },
  can_handle = air_quality_sensor_utils.is_matter_air_quality_sensor
}

return matter_air_quality_sensor_handler
