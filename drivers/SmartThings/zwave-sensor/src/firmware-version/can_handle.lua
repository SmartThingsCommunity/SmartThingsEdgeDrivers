-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

--This sub_driver will populate the currentVersion (firmware) when the firmwareUpdate capability is enabled
local FINGERPRINTS = {
  { manufacturerId = 0x027A, productType = 0x7000, productId = 0xE002 } -- Zooz ZSE42 Water Sensor
}

return function(opts, driver, device, ...)
  if device:supports_capability_by_id(capabilities.firmwareUpdate.ID) then
    for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
        local subDriver = require("firmware-version")
        return true, subDriver
      end
    end
  end
  return false
end