-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local defaults = require "st.zigbee.defaults"
local capabilities = require "st.capabilities"


local generic_motion_illuminance = {
  NAME = "Generic Motion illuminance",
  supported_capabilities = {
    capabilities.illuminanceMeasurement,
    capabilities.motionSensor
  },
  can_handle = require("motion-illuminance.can_handle"),
}
defaults.register_for_default_handlers(generic_motion_illuminance, generic_motion_illuminance.supported_capabilities)
return generic_motion_illuminance
