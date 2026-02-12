-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local SubscriptionMap = {
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
      clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels
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
  }
}

return SubscriptionMap
