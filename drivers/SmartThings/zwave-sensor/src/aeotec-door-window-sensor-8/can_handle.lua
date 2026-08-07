-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local AEOTEC_DOOR_WINDOW_SENSOR_8_FINGERPRINTS = {
  { manufacturerId = 0x0371, productId = 0x0037 }, -- Aeotec Door Window Sensor 8 EU/US/AU
  { manufacturerId = 0x0371, productId = 0x0039 } -- Aeotec Aerq 8 EU/US/AU
}

local function can_handle_aeotec_door_window_sensor_8(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_DOOR_WINDOW_SENSOR_8_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-door-window-sensor-8")
      return true, subdriver
    end
  end
  return false
end

return can_handle_aeotec_door_window_sensor_8