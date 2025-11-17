-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aurora_contact(opts, driver, device, ...)
  local FINGERPRINTS = require("aurora-contact-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("aurora-contact-sensor")
    end
  end
  return false
end

return can_handle_aurora_contact
