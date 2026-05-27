-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function frient_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "frient A/S" and (device:get_model() == "SBTZB-110" or device:get_model() == "MBTZB-110") then
    return true, require("frient")
  end
  return false
end

return frient_can_handle
