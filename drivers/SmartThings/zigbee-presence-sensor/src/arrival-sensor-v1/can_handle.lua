-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function arrival_sensor_v1_can_handle(opts, driver, device, ...)
  -- excluding Aqara device and tagv4
  return device:get_manufacturer() ~= "aqara" and device:get_model() ~= "tagv4"
end

return arrival_sensor_v1_can_handle
