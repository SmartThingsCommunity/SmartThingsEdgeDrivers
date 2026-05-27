-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function somfy_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "SOMFY" then
    return true, require("zigbee-multi-button.somfy")
  end
  return false
end

return somfy_can_handle
