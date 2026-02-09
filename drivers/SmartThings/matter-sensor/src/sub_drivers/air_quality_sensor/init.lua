-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local version = require "version"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local aqs_utils = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.utils"
local fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"
local attribute_handlers = require "sub_drivers.air_quality_sensor.air_quality_sensor_handlers.attribute_handlers"

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

-- AIR QUALITY SENSOR LIFECYCLE HANDLERS --

local AirQualitySensorLifecycleHandlers = {}

function AirQualitySensorLifecycleHandlers.do_configure(driver, device)
  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(fields.units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end
  if version.api >= 14 and version.rpc >= 8 then
    local modular_device_cfg = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.device_configuration"
    modular_device_cfg.match_profile(device)
  else
    local legacy_device_cfg = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.legacy_device_configuration"
    legacy_device_cfg.match_profile(device)
  end
end

function AirQualitySensorLifecycleHandlers.driver_switched(driver, device)
  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(fields.units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end
  if version.api >= 14 and version.rpc >= 8 then
    local modular_device_cfg = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.device_configuration"
    modular_device_cfg.match_profile(device)
  else
    local legacy_device_cfg = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.legacy_device_configuration"
    legacy_device_cfg.match_profile(device)
  end
end

function AirQualitySensorLifecycleHandlers.device_init(driver, device)
  if device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) and (version.api < 15 or version.rpc < 9) then
    -- assume that device is using a modular profile on 0.57 FW, override supports_capability_by_id
    -- library function to utilize optional capabilities
    device:extend_device("supports_capability_by_id", aqs_utils.supports_capability_by_id_modular)
  end
  aqs_utils.set_supported_health_concern_values(device)
  device:subscribe()
end

function AirQualitySensorLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id or
    aqs_utils.profile_changed(device.profile.components, args.old_st_store.profile.components) then
    if device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) then
      --re-up subscription with new capabilities using the modular supports_capability override
       device:extend_device("supports_capability_by_id", aqs_utils.supports_capability_by_id_modular)
    end
    aqs_utils.set_supported_health_concern_values(device)
    device:subscribe()
  end
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
        [clusters.AirQuality.attributes.AirQuality.ID] = attribute_handlers.air_quality_handler,
      },
      [clusters.CarbonDioxideConcentrationMeasurement.ID] = {
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.carbonDioxideMeasurement.NAME, capabilities.carbonDioxideMeasurement.carbonDioxide, fields.units.PPM),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.carbonDioxideMeasurement.NAME),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern),
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.carbonMonoxideMeasurement.NAME, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel, fields.units.PPM),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.carbonMonoxideMeasurement.NAME),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.carbonMonoxideHealthConcern.carbonMonoxideHealthConcern),
      },
      [clusters.FormaldehydeConcentrationMeasurement.ID] = {
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.formaldehydeMeasurement.NAME, capabilities.formaldehydeMeasurement.formaldehydeLevel, fields.units.PPM),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.formaldehydeMeasurement.NAME),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.formaldehydeHealthConcern.formaldehydeHealthConcern),
      },
      [clusters.NitrogenDioxideConcentrationMeasurement.ID] = {
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.nitrogenDioxideMeasurement.NAME, capabilities.nitrogenDioxideMeasurement.nitrogenDioxide, fields.units.PPM),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.nitrogenDioxideMeasurement.NAME),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.nitrogenDioxideHealthConcern.nitrogenDioxideHealthConcern)
      },
      [clusters.OzoneConcentrationMeasurement.ID] = {
        [clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.ozoneMeasurement.NAME, capabilities.ozoneMeasurement.ozone, fields.units.PPM),
        [clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.ozoneMeasurement.NAME),
        [clusters.OzoneConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.ozoneHealthConcern.ozoneHealthConcern)
      },
      [clusters.Pm1ConcentrationMeasurement.ID] = {
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.veryFineDustSensor.NAME, capabilities.veryFineDustSensor.veryFineDustLevel, fields.units.UGM3),
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.veryFineDustSensor.NAME),
        [clusters.Pm1ConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern),
      },
      [clusters.Pm10ConcentrationMeasurement.ID] = {
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.dustSensor.NAME, capabilities.dustSensor.dustLevel, fields.units.UGM3),
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.dustSensor.NAME),
        [clusters.Pm10ConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.dustHealthConcern.dustHealthConcern),
      },
      [clusters.Pm25ConcentrationMeasurement.ID] = {
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.fineDustSensor.NAME, capabilities.fineDustSensor.fineDustLevel, fields.units.UGM3),
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.fineDustSensor.NAME),
        [clusters.Pm25ConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.fineDustHealthConcern.fineDustHealthConcern),
      },
      [clusters.PressureMeasurement.ID] = {
        [clusters.PressureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.pressure_measured_value_handler
      },
      [clusters.RadonConcentrationMeasurement.ID] = {
        [clusters.RadonConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.radonMeasurement.NAME, capabilities.radonMeasurement.radonLevel, fields.units.PCIL),
        [clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.radonMeasurement.NAME),
        [clusters.RadonConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.radonHealthConcern.radonHealthConcern)
      },
      [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID] = {
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.measured_value_factory(capabilities.tvocMeasurement.NAME, capabilities.tvocMeasurement.tvocLevel, fields.units.PPB),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.measurement_unit_factory(capabilities.tvocMeasurement.NAME),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.level_value_factory(capabilities.tvocHealthConcern.tvocHealthConcern)
      }
    }
  },
  can_handle = require("sub_drivers.air_quality_sensor.can_handle")
}

return matter_air_quality_sensor_handler
