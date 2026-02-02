-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_frient_power_meter = function(opts, driver, device)
  local FINGERPRINTS = require("frient.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true, require("frient")
    end
  end

  return false
end

return is_frient_power_meter
