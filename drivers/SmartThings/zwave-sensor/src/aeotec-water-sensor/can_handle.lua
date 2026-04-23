-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zwave_water_temp_humidity_sensor(opts, driver, device, ...)
  local FINGERPRINTS = require("aeotec-water-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-water-sensor")
      return true, subdriver
    end
  end
  return false
end

return can_handle_zwave_water_temp_humidity_sensor
