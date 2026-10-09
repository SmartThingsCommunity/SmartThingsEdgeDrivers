-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aeotec_doorbell_siren(opts, driver, device, ...)
  local FINGERPRINTS = require("aeotec-doorbell-siren.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("aeotec-doorbell-siren")
    end
  end
  return false
end

return can_handle_aeotec_doorbell_siren
