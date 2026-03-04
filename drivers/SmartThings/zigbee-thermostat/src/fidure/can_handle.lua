-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function fidure_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Fidure" and device:get_model() == "A1732R3" then
    return true, require("fidure")
  end
  return false
end

return fidure_can_handle
