-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local can_handle_ikea = function(opts, driver, device)
  local FINGERPRINTS = require("zigbee-multi-button.ikea.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr then
      return true, require("zigbee-multi-button.ikea")
    end
  end
  return false
end

return can_handle_ikea
