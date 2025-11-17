-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_motion_sensor = function(opts, driver, device)
  if device:supports_capability(capabilities.motionSensor) and not device:supports_capability(capabilities.illuminanceMeasurement) then
    return true, require("motion")
  end
end

return is_motion_sensor
