-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function leviton_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "HAI" and device:get_model() == "65A01-1" then
    return true, require("leviton")
  end
  return false
end

return leviton_can_handle
