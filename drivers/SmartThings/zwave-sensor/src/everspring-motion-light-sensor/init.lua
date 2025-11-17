-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2,strict=true})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})

local EVERSPRING_MOTION_LIGHT_FINGERPRINT = { mfr = 0x0060, prod = 0x0012, model = 0x0001 }

local function can_handle_everspring_motion_light(opts, driver, device, ...)
  if device:id_match(
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.mfr,
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.prod,
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.model
  ) then
    local subdriver = require("everspring-motion-light-sensor")
    return true, subdriver
  else return false end
end

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
