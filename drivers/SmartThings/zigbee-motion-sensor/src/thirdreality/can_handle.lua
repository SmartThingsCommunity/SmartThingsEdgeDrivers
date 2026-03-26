-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_third_reality_motion_sensor = function(opts, driver, device)
  local FINGERPRINTS = require("thirdreality.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("thirdreality")
    end
  end
  return false
end

return is_third_reality_motion_sensor
