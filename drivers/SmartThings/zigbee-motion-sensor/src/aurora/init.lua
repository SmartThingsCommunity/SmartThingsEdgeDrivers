-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

local function added_handler(self, device)
  -- Aurora Smart PIR Sensor doesn't report when there is no motion during pairing process
  -- reports are sent only if there is motion detected, so fake event is needed here
  device:emit_event(capabilities.motionSensor.motion.inactive())
end

local aurora_motion_driver = {
  NAME = "Aurora Motion Sensor",
  lifecycle_handlers = {
    added = added_handler,
  },
  can_handle = require("aurora.can_handle"),
}

return aurora_motion_driver
