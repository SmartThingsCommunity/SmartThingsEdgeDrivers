-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function sinope_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Sinope Technologies" then
    return true, require("sinope")
  end
  return false
end

return sinope_can_handle
