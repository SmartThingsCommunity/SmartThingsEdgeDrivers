-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local fields = require "switch_utils.fields"
local sensor_fields = require "sub_drivers.sensor.switch_sensor_utils.fields"
local attribute_handlers = require "sub_drivers.sensor.sensor_handlers.attribute_handlers"

local sensor_handler = {
  NAME = "Matter Sensor Handlers",
  can_handle = require("sub_drivers.sensor.can_handle"),
  matter_handlers = {
    attr = {
      [clusters.BooleanState.ID] = {
        [clusters.BooleanState.attributes.StateValue.ID] = attribute_handlers.boolean_state_value_handler
      },
      [clusters.BooleanStateConfiguration.ID] = {
        [clusters.BooleanStateConfiguration.attributes.SensorFault.ID] = attribute_handlers.sensor_fault_handler,
        [clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels.ID] = attribute_handlers.supported_sensitivity_levels_handler,
        [clusters.BooleanStateConfiguration.attributes.AttributeList.ID] = attribute_handlers.boolean_state_configuration_attribute_list_handler,
      },
      [clusters.FlowMeasurement.ID] = {
        [clusters.FlowMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.flow_measured_value_handler,
        [clusters.FlowMeasurement.attributes.MinMeasuredValue.ID] = attribute_handlers.flow_measured_value_bounds_factory(sensor_fields.FLOW_MIN),
        [clusters.FlowMeasurement.attributes.MaxMeasuredValue.ID] = attribute_handlers.flow_measured_value_bounds_factory(sensor_fields.FLOW_MAX)
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.illuminance_measured_value_handler
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = attribute_handlers.occupancy_measured_value_handler,
      },
      [clusters.PressureMeasurement.ID] = {
        [clusters.PressureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.pressure_measured_value_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.humidity_measured_value_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.temperature_measured_value_handler,
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.TEMP_MIN),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.TEMP_MAX),
      },
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.LocalTemperature.ID] = attribute_handlers.temperature_measured_value_handler -- TemperatureMeasurement.MeasuredValue handler can support this attibute
      },
    }
  },
  subscribed_attributes = {
    [capabilities.atmosphericPressureMeasurement.ID] = {
      clusters.PressureMeasurement.attributes.MeasuredValue
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
      clusters.BooleanStateConfiguration.attributes.SensorFault,
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
  },
  supported_capabilities = {
    capabilities.atmosphericPressureMeasurement,
    capabilities.contactSensor,
    capabilities.flowMeasurement,
    capabilities.hardwareFault,
    capabilities.illuminanceMeasurement,
    capabilities.motionSensor,
    capabilities.presenceSensor,
    capabilities.rainSensor,
    capabilities.relativeHumidityMeasurement,
    capabilities.temperatureAlarm,
    capabilities.temperatureMeasurement,
    capabilities.waterSensor,
  },
}

return sensor_handler
