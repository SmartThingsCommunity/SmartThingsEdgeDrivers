-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aeotec_multisensor(opts, self, device, ...)
  local FINGERPRINTS = require("aeotec-multisensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-multisensor")
      return true, subdriver, require("aeotec-multisensor")
    end
  end
  return false
end

return can_handle_aeotec_multisensor
