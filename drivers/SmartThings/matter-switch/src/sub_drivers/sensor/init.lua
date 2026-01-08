-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local sensor_fields = require "sub_drivers.sensor.utils.fields"
local attribute_handlers = require "sub_drivers.sensor.handlers.attribute_handlers"

local sensor_handler = {
  NAME = "Matter Sensor Handlers",
  can_handle = require("sub_drivers.sensor.can_handle"),
  matter_handlers = {
    attr = {
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.illuminance_measured_value_handler
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = attribute_handlers.occupancy_measured_value_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.humidity_measured_value_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.temperature_measured_value_handler,
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(sensor_fields.TEMP_MIN),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(sensor_fields.TEMP_MAX),
      },
    }
  }
}

return sensor_handler
