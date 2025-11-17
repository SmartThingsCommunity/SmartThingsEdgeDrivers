-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_water_sensor = function(opts, driver, device)
  if device:supports_capability(capabilities.waterSensor) then
    return true, require("waterleak")
  end
end

return is_water_sensor
