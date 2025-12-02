-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local function can_handle_eaton_anyplace_switch(opts, driver, device, ...)
  local fingerprints = {
    { manufacturerId = 0x001A, productType = 0x4243, productId = 0x0000 } -- Eaton Anyplace Switch
  }
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("eaton-anyplace-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_eaton_anyplace_switch
