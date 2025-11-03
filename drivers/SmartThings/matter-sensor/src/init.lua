-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"
local version = require "version"

local fields = require "sensor_utils.fields"
local device_cfg = require "sensor_utils.device_configuration"
local attribute_handlers = require "sensor_handlers.attribute_handlers"

-- This can be removed once LuaLibs supports the PressureMeasurement cluster
if not pcall(function(cluster) return clusters[cluster] end,
             "PressureMeasurement") then
  clusters.PressureMeasurement = require "PressureMeasurement"
end

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
  clusters.SmokeCoAlarm = require "embedded_clusters.SmokeCoAlarm"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "embedded_clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement"
end

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.BooleanStateConfiguration = require "embedded_clusters.BooleanStateConfiguration"
end

local SensorLifecycleHandlers = {}

function SensorLifecycleHandlers.do_configure(driver, device)
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    device:send(clusters.PowerSource.attributes.AttributeList:read())
  else
    device_cfg.match_profile(driver, device, fields.battery_support.NO_BATTERY)
  end
end

function SensorLifecycleHandlers.device_init(driver, device)
  device.log.info("device init")
  device_cfg.set_boolean_device_type_per_endpoint(driver, device)
  device:subscribe()
end

function SensorLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device_cfg.set_boolean_device_type_per_endpoint(driver, device)
    device:subscribe()
  end
  if not device.preferences then
    return
  end
  for dt_name, info in pairs(fields.BOOLEAN_DEVICE_TYPE_INFO) do
    local dt_ep = device:get_field(dt_name)
    if dt_ep and info.sensitivity_preference and (device.preferences[info.sensitivity_preference] ~= args.old_st_store.preferences[info.sensitivity_preference]) then
      local sensitivity_preference = device.preferences[info.sensitivity_preference]
      if sensitivity_preference == "2" then -- high
        local max_sensitivity_level = device:get_field(info.sensitivity_max) - 1
        device:send(clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(device, dt_ep, max_sensitivity_level))
      elseif sensitivity_preference == "1" then -- medium
        local medium_sensitivity_level = math.floor((device:get_field(info.sensitivity_max) + 1) / 2)
        device:send(clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(device, dt_ep, medium_sensitivity_level))
      elseif sensitivity_preference == "0" then -- low
        local min_sensitivity_level = 0
        device:send(clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(device, dt_ep, min_sensitivity_level))
      end
    end
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    doConfigure = SensorLifecycleHandlers.do_configure,
    init = SensorLifecycleHandlers.device_init,
    infoChanged = SensorLifecycleHandlers.info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.humidity_measured_value_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.temperature_measured_value_handler,
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.TEMP_MIN),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.TEMP_MAX),
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.illuminance_measured_value_handler
      },
      [clusters.BooleanState.ID] = {
        [clusters.BooleanState.attributes.StateValue.ID] = attribute_handlers.boolean_state_value_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = attribute_handlers.power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = attribute_handlers.bat_charge_level_handler,
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = attribute_handlers.bat_percent_remaining_handler,
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = attribute_handlers.occupancy_measured_value_handler,
      },
      [clusters.PressureMeasurement.ID] = {
        [clusters.PressureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.pressure_measured_value_handler,
      },
      [clusters.BooleanStateConfiguration.ID] = {
        [clusters.BooleanStateConfiguration.attributes.SensorFault.ID] = attribute_handlers.sensor_fault_handler,
        [clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels.ID] = attribute_handlers.supported_sensitivity_levels_handler,
      },
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.LocalTemperature.ID] = attribute_handlers.temperature_measured_value_handler -- TemperatureMeasurement:MeasuredValue handler can support this attibute
      },
      [clusters.FlowMeasurement.ID] = {
        [clusters.FlowMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.flow_measured_value_handler,
        [clusters.FlowMeasurement.attributes.MinMeasuredValue.ID] = attribute_handlers.flow_measured_value_bounds_factory(fields.FLOW_MIN),
        [clusters.FlowMeasurement.attributes.MaxMeasuredValue.ID] = attribute_handlers.flow_measured_value_bounds_factory(fields.FLOW_MAX)
      }
    }
  },
  subscribed_attributes = {
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    },
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel,
      clusters.SmokeCoAlarm.attributes.BatteryAlert,
    },
    [capabilities.contactSensor.ID] = {
      clusters.BooleanState.attributes.StateValue
    },
    [capabilities.flowMeasurement.ID] = {
      clusters.FlowMeasurement.attributes.MeasuredValue,
      clusters.FlowMeasurement.attributes.MinMeasuredValue,
      clusters.FlowMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.hardwareFault.ID] = {
      clusters.SmokeCoAlarm.attributes.HardwareFaultAlert,
      clusters.BooleanStateConfiguration.attributes.SensorFault,
      clusters.SmokeCoAlarm.attributes.BatteryAlert,
      clusters.PowerSource.attributes.BatChargeLevel,
    },
    [capabilities.illuminanceMeasurement.ID] = {
      clusters.IlluminanceMeasurement.attributes.MeasuredValue
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    },
    [capabilities.presenceSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    },
    [capabilities.rainSensor.ID] = {
      clusters.BooleanState.attributes.StateValue,
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.temperatureAlarm.ID] = {
      clusters.BooleanState.attributes.StateValue,
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
      clusters.Thermostat.attributes.LocalTemperature
    },
    [capabilities.waterSensor.ID] = {
      clusters.BooleanState.attributes.StateValue,
    },
    [capabilities.airQualityHealthConcern.ID] = {
      clusters.AirQuality.attributes.AirQuality
    },
    [capabilities.atmosphericPressureMeasurement.ID] = {
      clusters.PressureMeasurement.attributes.MeasuredValue
    },
    [capabilities.carbonDioxideHealthConcern.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.carbonDioxideMeasurement.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonMonoxideHealthConcern.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.dustHealthConcern.ID] = {
      clusters.Pm10ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.dustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.fineDustHealthConcern.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.fineDustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.formaldehydeHealthConcern.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.formaldehydeMeasurement.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.nitrogenDioxideHealthConcern.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.nitrogenDioxideMeasurement.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.ozoneHealthConcern.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.ozoneMeasurement.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
      clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.radonHealthConcern.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.radonMeasurement.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
      clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.tvocHealthConcern.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue
    },
    [capabilities.tvocMeasurement.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.veryFineDustHealthConcern.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.veryFineDustSensor.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonMonoxideDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.COState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.SmokeState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress,
      clusters.Switch.events.LongPress,
      clusters.Switch.events.MultiPressComplete,
    }
  },
  capability_handlers = {},
  supported_capabilities = {
    capabilities.temperatureMeasurement,
    capabilities.contactSensor,
    capabilities.motionSensor,
    capabilities.presenceSensor,
    capabilities.button,
    capabilities.battery,
    capabilities.batteryLevel,
    capabilities.relativeHumidityMeasurement,
    capabilities.illuminanceMeasurement,
    capabilities.atmosphericPressureMeasurement,
    capabilities.waterSensor,
    capabilities.temperatureAlarm,
    capabilities.rainSensor,
    capabilities.hardwareFault,
    capabilities.flowMeasurement,
  },
  sub_drivers = {
    require("sub_drivers.air_quality_sensor"),
    require("sub_drivers.smoke_co_alarm"),
    require("sub_drivers.bosch_button_contact")
  }
}

local matter_driver = MatterDriver("matter-sensor", matter_driver_template)
matter_driver:run()
