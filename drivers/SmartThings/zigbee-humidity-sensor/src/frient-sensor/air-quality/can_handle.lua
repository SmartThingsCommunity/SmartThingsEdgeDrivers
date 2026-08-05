-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_frient(opts, driver, device, ...)
    local FRIENT_AIR_QUALITY_SENSOR_FINGERPRINTS = require ("frient-sensor.air-quality.fingerprints")
    for _, fingerprint in ipairs(FRIENT_AIR_QUALITY_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model and fingerprint.subdriver == "airquality" then
      return true, require("frient-sensor.air-quality")
    end
  end
  return false
end

return can_handle_frient
