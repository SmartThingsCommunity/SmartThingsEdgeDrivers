-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_fan_3_speed(opts, driver, device, ...)
  local FINGERPRINTS = require("zwave-fan-3-speed.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("zwave-fan-3-speed")
    end
  end
  return false
end

return is_fan_3_speed
