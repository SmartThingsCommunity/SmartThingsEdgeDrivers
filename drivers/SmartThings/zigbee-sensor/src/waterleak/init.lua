-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local defaults = require "st.zigbee.defaults"
local capabilities = require "st.capabilities"


local generic_water_sensor = {
  NAME = "Generic Water Sensor",
  supported_capabilities = {
    capabilities.waterSensor
  },
  can_handle = require("waterleak.can_handle"),
}
defaults.register_for_default_handlers(generic_water_sensor, generic_water_sensor.supported_capabilities)
return generic_water_sensor
