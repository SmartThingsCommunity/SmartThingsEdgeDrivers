-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function frient_keypad_can_handle(opts, driver, device, ...)
  local FINGERPRINTS = require("frient-keypad.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("frient-keypad")
    end
  end
  return false
end

return frient_keypad_can_handle
