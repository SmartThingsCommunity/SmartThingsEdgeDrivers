-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Check if a given device matches the supported fingerprints
local function is_zunzunbee_button(opts, driver, device)
  local ZUNZUNBEE_BUTTON_FINGERPRINTS = require "zigbee-multi-button.zunzunbee.fingerprints"
  for _, fingerprint in ipairs(ZUNZUNBEE_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("zigbee-multi-button.zunzunbee")
    end
  end
  return false
end

return is_zunzunbee_button
