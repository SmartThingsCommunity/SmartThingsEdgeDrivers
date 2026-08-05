-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function zigbee_water_freeze_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Ecolink" and device:get_model() == "FLZB1-ECO" then
    return true, require("zigbee-water-freeze")
  end
  return false
end

return zigbee_water_freeze_can_handle
