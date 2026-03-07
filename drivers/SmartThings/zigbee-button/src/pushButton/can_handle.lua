-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function pushButton_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "HEIMAN" and device:get_model() == "SOS-EM" then
    return true, require("pushButton")
  end
  return false
end

return pushButton_can_handle
