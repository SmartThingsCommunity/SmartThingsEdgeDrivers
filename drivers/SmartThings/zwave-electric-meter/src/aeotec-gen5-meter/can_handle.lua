-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aeotec_gen5_meter(opts, driver, device, ...)
  local FINGERPRINTS = require("aeotec-gen5-meter.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("aeotec-gen5-meter")
    end
  end
  return false
end

return can_handle_aeotec_gen5_meter
