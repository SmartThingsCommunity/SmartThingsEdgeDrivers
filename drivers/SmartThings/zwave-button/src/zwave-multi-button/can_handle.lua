-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zwave_multi_button(opts, driver, device, ...)
  local FINGERPRINTS = require("zwave-multi-button.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("zwave-multi-button")
    end
  end
  return false
end

return can_handle_zwave_multi_button
