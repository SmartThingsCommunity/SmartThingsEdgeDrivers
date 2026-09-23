-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local AEOTEC_WATER_SENSOR_8_FINGERPRINTS = {
  { manufacturerId = 0x0371, productId = 0x0038 } -- Aeotec Water Sensor 8 EU/US/AU
}

local function can_handle_aeotec_water_sensor_8(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_WATER_SENSOR_8_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-water-sensor-8")
      return true, subdriver
    end
  end
  return false
end

return can_handle_aeotec_water_sensor_8