-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, ...)
  local ROBB_MFR_STRING = "ROBB smarrt"
  local WIRELESS_REMOTE_FINGERPRINTS = require "zigbee-multi-button.robb.fingerprints"

  if device:get_manufacturer() == ROBB_MFR_STRING and WIRELESS_REMOTE_FINGERPRINTS[device:get_model()] then
    return true, require("zigbee-multi-button.robb")
  else
    return false
  end
end

return can_handle
