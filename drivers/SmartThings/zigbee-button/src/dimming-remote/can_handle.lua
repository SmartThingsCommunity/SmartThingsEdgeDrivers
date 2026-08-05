-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zigbee_dimming_remote(opts, driver, device, ...)
  local FINGERPRINTS = require("dimming-remote.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("dimming-remote")
    end
  end
  return false
end

return can_handle_zigbee_dimming_remote
