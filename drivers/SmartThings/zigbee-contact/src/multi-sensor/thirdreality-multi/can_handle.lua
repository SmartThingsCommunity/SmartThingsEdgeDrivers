-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function thirdreality_multi_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Third Reality, Inc" then
    return true, require("multi-sensor.thirdreality-multi")
  end
  return false
end

return thirdreality_multi_can_handle
