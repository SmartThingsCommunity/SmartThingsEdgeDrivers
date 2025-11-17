-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_motion_illuminance = function(opts, driver, device)
  if device:supports_capability(capabilities.motionSensor) and device:supports_capability(capabilities.illuminanceMeasurement) then
    return true, require("motion-illuminance")
  end
end

return is_motion_illuminance
