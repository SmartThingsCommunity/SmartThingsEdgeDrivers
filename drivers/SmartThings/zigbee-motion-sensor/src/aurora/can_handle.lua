-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function aurora_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Aurora" and device:get_model() == "MotionSensor51AU" then
    return true, require("aurora")
  end
  return false
end

return aurora_can_handle
