-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function arrival_sensor_v1_can_handle(opts, driver, device, ...)
  -- excluding Aqara device and tagv4
  if device:get_manufacturer() ~= "aqara" and device:get_model() ~= "tagv4" then
    return true, require("arrival-sensor-v1")
  end
  return false
end

return arrival_sensor_v1_can_handle
