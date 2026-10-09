-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_roller_shutter(opts, driver, device, ...)
  local FINGERPRINTS = require("window-treatment-venetian.fibaro-roller-shutter.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("window-treatment-venetian.fibaro-roller-shutter")
    end
  end
  return false
end

return can_handle_fibaro_roller_shutter
