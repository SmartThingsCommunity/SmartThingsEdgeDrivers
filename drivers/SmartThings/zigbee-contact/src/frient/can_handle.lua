-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function frient_can_handle(opts, driver, device, ...)
  if (device:get_manufacturer() == "frient A/S") and
    (device:get_model() == "WISZB-120" or
    device:get_model() == "WISZB-121" or
    device:get_model() == "WISZB-131" or
    device:get_model() == "WISZB-137") then
      return true, require("frient")
  end
  return false
end

return frient_can_handle
