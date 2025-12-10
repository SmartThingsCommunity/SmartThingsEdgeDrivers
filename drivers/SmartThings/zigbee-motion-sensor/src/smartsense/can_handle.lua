-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, ...)

  local SMARTSENSE_MFR = "SmartThings"
  local SMARTSENSE_MODEL = "PGC314"
  local SMARTSENSE_PROFILE_ID = 0xFC01

  local endpoint = device.zigbee_endpoints[1] or device.zigbee_endpoints["1"]
  if (device:get_manufacturer() == SMARTSENSE_MFR and device:get_model() == SMARTSENSE_MODEL) or
    endpoint.profile_id == SMARTSENSE_PROFILE_ID then
    return true, require("smartsense")
  end
  return false
end

return can_handle
