-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == ROBB_MFR_STRING and WIRELESS_REMOTE_FINGERPRINTS[device:get_model()] then
    return true, require("robb")
  else
    return false
  end
end

return can_handle
