-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_multifunctional_siren(opts, driver, device, ...)
  local FINGERPRINTS = require("zooz-zse50.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("zooz-zse50")
    end
  end
  return false
end

return can_handle_multifunctional_siren
