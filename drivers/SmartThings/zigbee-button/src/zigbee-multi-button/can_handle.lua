-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zigbee_multi_button(opts, driver, device, ...)
  local FINGERPRINTS = require("zigbee-multi-button.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("zigbee-multi-button")
    end
  end
  return false
end

return can_handle_zigbee_multi_button
