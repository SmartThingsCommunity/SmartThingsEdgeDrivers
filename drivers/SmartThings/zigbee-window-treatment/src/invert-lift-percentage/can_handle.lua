-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function invert_lift_percentage_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "IKEA of Sweden" or
    device:get_manufacturer() == "Smartwings" or
    device:get_manufacturer() == "Insta GmbH" or
    (device:get_manufacturer() == "Third Reality, Inc" and device:get_model() == "3RSB015BZ")
  then
      return true, require("invert-lift-percentage")
  end
  return false
end

return invert_lift_percentage_can_handle
