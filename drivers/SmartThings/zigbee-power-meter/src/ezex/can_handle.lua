-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_ezex_power_meter = function(opts, driver, device)
  local FINGERPRINTS = require("ezex.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:get_model() == fingerprint.model then
          return true, require("ezex")
      end
  end

  return false
end

return is_ezex_power_meter
