-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function samjin_multi_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Samjin" then
    return true, require("multi-sensor.samjin-multi")
  end
  return false
end

return samjin_multi_can_handle
