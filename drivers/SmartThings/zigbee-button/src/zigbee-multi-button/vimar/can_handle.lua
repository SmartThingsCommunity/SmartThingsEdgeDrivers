-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function vimar_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Vimar" and device:get_model() == "RemoteControl_v1.0" then
    return true, require("zigbee-multi-button.vimar")
  end
  return false
end

return vimar_can_handle
