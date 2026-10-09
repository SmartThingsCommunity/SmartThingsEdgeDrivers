-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, ...)
  local SMARTSENSE_PROFILE_ID = 0xFC01
  local FINGERPRINTS = require("smartsense-multi.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("smartsense-multi")
    end
  end
  local endpoint = device.zigbee_endpoints[1] or device.zigbee_endpoints["1"]
  if endpoint.profile_id == SMARTSENSE_PROFILE_ID then return true end
  return false
end

return can_handle
