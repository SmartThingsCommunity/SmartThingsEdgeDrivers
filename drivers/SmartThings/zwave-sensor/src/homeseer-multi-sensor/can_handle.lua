-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Determine whether the passed device is homeseer multi sensor
---
--- @param driver Driver driver instance
--- @param device Device device instance
--- @return boolean true if the device proper, else false
local function can_handle_homeseer_multi_sensor(opts, driver, device, ...)
    local HOMESEER_MULTI_SENSOR_FINGERPRINTS = { manufacturerId = 0x001E, productType = 0x0002, productId = 0x0001 } -- Homeseer multi sensor HSM100
    if device:id_match(
      HOMESEER_MULTI_SENSOR_FINGERPRINTS.manufacturerId,
      HOMESEER_MULTI_SENSOR_FINGERPRINTS.productType,
      HOMESEER_MULTI_SENSOR_FINGERPRINTS.productId) then
        return true, require("homeseer-multi-sensor")
    end
    return false
end

return can_handle_homeseer_multi_sensor
