-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_shinasystem_button = function(opts, driver, device)
  local FINGERPRINTS = require("zigbee-multi-button.shinasystems.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("zigbee-multi-button.shinasystems")
    end
  end
  return false
end

return is_shinasystem_button
