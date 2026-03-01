-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_motion_sensor(opts, driver, device, ...)

  local FIBARO_MOTION_MFR = 0x010F
  local FIBARO_MOTION_PROD = 0x0800
  if device:id_match(FIBARO_MOTION_MFR, FIBARO_MOTION_PROD) then
    local subdriver = require("fibaro-motion-sensor")
    return true, subdriver
  end
  return false
end

return can_handle_fibaro_motion_sensor
