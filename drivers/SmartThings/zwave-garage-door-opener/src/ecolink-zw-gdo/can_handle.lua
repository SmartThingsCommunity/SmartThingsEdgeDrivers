-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_ecolink_garage_door(opts, driver, device, ...)
  local FINGERPRINTS = require("ecolink-zw-gdo.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("ecolink-zw-gdo")
    end
  end
  return false
end

return can_handle_ecolink_garage_door
