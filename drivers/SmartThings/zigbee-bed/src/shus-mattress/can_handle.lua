-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_shus_products(opts, driver, device)
  local FINGERPRINTS = require("shus-mattress.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("shus-mattress")
    end
  end
  return false
end

return is_shus_products
