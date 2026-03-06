-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_shelly_wave_i4(opts, driver, device, ...)
  local FINGERPRINTS = require("zwave-multi-button.shelly_wave_i4.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("shelly_wave_i4")
    end
  end
  return false
end

return can_handle_shelly_wave_i4
