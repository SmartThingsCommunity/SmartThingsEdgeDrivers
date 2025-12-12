-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zooz_4_in_1_sensor(opts, driver, device, ...)
  local FINGERPRINTS = require("zooz-4-in-1-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("zooz-4-in-1-sensor")
      return true, subdriver, require("zooz-4-in-1-sensor")
    end
  end
  return false
end

return can_handle_zooz_4_in_1_sensor
