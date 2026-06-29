-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function curtain_driver_e1_can_handle(opts, driver, device, ...)
  if device:get_model() == "lumi.curtain.agl001" then
    return true, require("aqara.curtain-driver-e1")
  end
  return false
end

return curtain_driver_e1_can_handle
