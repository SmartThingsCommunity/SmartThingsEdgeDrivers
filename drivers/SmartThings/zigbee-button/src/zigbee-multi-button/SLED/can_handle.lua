-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function SLED_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Samsung Electronics" and device:get_model() == "SAMSUNG-ITM-Z-005" then
    return true, require("zigbee-multi-button.SLED")
  end
  return false
end

return SLED_can_handle
