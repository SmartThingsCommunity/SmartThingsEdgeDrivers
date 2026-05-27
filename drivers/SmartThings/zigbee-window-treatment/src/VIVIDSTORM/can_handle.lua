-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_zigbee_window_shade = function(opts, driver, device)
  local FINGERPRINTS = require("VIVIDSTORM.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("VIVIDSTORM")
    end
  end
  return false
end

return is_zigbee_window_shade
