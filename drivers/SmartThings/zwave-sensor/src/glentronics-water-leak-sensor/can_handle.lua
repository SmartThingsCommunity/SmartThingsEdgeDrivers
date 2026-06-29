-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Determine whether the passed device is glentronics water leak sensor
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_glentronics_water_leak_sensor(opts, driver, device, ...)
  local GLENTRONICS_WATER_LEAK_SENSOR_FINGERPRINTS = { manufacturerId = 0x0084, productType = 0x0093, productId = 0x0114 } -- glentronics water leak sensor
  if device:id_match(
      GLENTRONICS_WATER_LEAK_SENSOR_FINGERPRINTS.manufacturerId,
      GLENTRONICS_WATER_LEAK_SENSOR_FINGERPRINTS.productType,
      GLENTRONICS_WATER_LEAK_SENSOR_FINGERPRINTS.productId) then
    return true, require("glentronics-water-leak-sensor")
  end
  return false
end

return can_handle_glentronics_water_leak_sensor
