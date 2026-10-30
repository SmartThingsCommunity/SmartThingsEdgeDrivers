-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_heatit_ztrm6(opts, driver, device, cmd, ...)
  local FINGERPRINTS = require("heatit-ztrm6.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("heatit-ztrm6")
    end
  end

  return false
end

return can_handle_heatit_ztrm6
