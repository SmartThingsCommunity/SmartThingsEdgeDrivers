-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function smartthings_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "SmartThings" then
    return true, require("smartthings")
  end
  return false
  end

return smartthings_can_handle
