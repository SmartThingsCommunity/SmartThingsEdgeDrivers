-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Matches multi-endpoint Aqara switches/modules listed in aqara/multi-switch/fingerprints.lua
-- (devices that create child devices for their extra switch endpoints).
return function(opts, driver, device)
  local FINGERPRINTS = require("aqara.multi-switch.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("aqara.multi-switch")
    end
  end
  return false
end
