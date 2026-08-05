-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_shinasystems_power_meter = function(opts, driver, device)
  local FINGERPRINTS = require("shinasystems.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true, require("shinasystems")
    end
  end

  return false
end

return is_shinasystems_power_meter
