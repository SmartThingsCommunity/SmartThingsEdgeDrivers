-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aeon_multiwhite_bulb(opts, driver, device, ...)
  local FINGERPRINTS = require("aeon-multiwhite-bulb.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("aeon-multiwhite-bulb")
    end
  end
  return false
end

return can_handle_aeon_multiwhite_bulb
