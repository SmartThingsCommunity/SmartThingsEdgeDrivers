-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_ct100_thermostat(opts, driver, device)
    local CT100_THERMOSTAT_FINGERPRINTS = require "ct100-thermostat.fingerprints"
    for _, fingerprint in ipairs(CT100_THERMOSTAT_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require "ct100-thermostat"
    end
  end

  return false
end

return can_handle_ct100_thermostat
