-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function samjin_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Samjin" and device:get_model() == "button" then
    return true, require("samjin")
  end
  return false
end

return samjin_can_handle
