-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2,strict=true})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})

local function device_added(driver, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:send(SwitchBinary:Get({}))
  device:send(SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }))
end

local everspring_motion_light = {
  NAME = "Everspring Motion Light",
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = require("everspring-motion-light-sensor.can_handle"),
}

return everspring_motion_light
