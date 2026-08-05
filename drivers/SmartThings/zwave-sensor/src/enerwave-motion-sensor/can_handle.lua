-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_enerwave_motion_sensor(opts, driver, device, cmd, ...)
  local ENERWAVE_MFR = 0x011A
  if device.zwave_manufacturer_id == ENERWAVE_MFR then
    local subdriver = require("enerwave-motion-sensor")
    return true, subdriver
  else return false end
end

return can_handle_enerwave_motion_sensor
