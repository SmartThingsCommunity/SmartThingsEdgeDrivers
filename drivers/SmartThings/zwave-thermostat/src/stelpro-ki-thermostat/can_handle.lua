-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_stelpro_ki_thermostat(opts, driver, device, cmd, ...)
  local FINGERPRINTS = require("stelpro-ki-thermostat.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("stelpro-ki-thermostat")
    end
  end

  return false
end

return can_handle_stelpro_ki_thermostat
