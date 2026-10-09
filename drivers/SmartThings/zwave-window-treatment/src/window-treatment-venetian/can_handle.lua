-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_window_treatment_venetian(opts, driver, device, ...)
  local FINGERPRINTS = require("window-treatment-venetian.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("window-treatment-venetian")
    end
  end
  return false
end

return can_handle_window_treatment_venetian
