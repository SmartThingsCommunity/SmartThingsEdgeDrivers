-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function ecosmart_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "LDS" and device:get_model() == "ZBT-CCTSwitch-D0001" then
    return true, require("zigbee-multi-button.ecosmart")
  end
  return false
end

return ecosmart_can_handle
