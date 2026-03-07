-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function leaksmart_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "WAXMAN" and device:get_model() == "leakSMART Water Sensor V2" then
    return true, require("leaksmart")
  end
  return false
end

return leaksmart_can_handle
