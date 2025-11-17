-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local defaults = require "st.zigbee.defaults"
local capabilities = require "st.capabilities"


local generic_motion_sensor = {
  NAME = "Generic Motion Sensor",
  supported_capabilities = {
    capabilities.motionSensor
  },
  can_handle = require("motion.can_handle"),
}
defaults.register_for_default_handlers(generic_motion_sensor, generic_motion_sensor.supported_capabilities)
return generic_motion_sensor
