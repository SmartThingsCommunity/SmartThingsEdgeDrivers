-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_smoke_sensor(opts, driver, device, cmd, ...)
  local FINGERPRINTS = require("fibaro-smoke-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("fibaro-smoke-sensor")
    end
  end
  return false
end

return can_handle_fibaro_smoke_sensor
