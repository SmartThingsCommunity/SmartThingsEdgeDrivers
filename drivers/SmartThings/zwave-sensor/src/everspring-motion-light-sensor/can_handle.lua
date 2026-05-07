-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_everspring_motion_light(opts, driver, device, ...)
  local EVERSPRING_MOTION_LIGHT_FINGERPRINT = { mfr = 0x0060, prod = 0x0012, model = 0x0001 }
  if device:id_match(
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.mfr,
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.prod,
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.model
  ) then
    local subdriver = require("everspring-motion-light-sensor")
    return true, subdriver
  end
  return false
end

return can_handle_everspring_motion_light
