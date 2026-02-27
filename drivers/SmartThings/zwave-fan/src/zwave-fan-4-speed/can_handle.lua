-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fan_4_speed(opts, driver, device, ...)
  local FINGERPRINTS = require("zwave-fan-4-speed.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("zwave-fan-4-speed")
    end
  end
  return false
end

return can_handle_fan_4_speed
