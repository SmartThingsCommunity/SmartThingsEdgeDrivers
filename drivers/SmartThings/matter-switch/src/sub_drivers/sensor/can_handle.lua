-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local fields = require "switch_utils.fields"

return function(opts, driver, device)
  for _, capability in pairs(driver.sub_drivers.sensor.supported_capabilities) do
    if device:supports_capability(capability) then
      device:set_field(fields.SENSOR_SUBDRIVER_LOADED, true)
      return true, require("sub_drivers.sensor")
    end
  end
  return false
end
