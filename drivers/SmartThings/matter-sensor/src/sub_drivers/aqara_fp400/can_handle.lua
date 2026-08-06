-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_aqara_fp400(opts, driver, device)
  local sensor_utils = require "sensor_utils.utils"
  if sensor_utils.get_product_override_field(device, "is_aqara_fp400") then
    return true, require("sub_drivers.aqara_fp400")
  end
  return false
end

return is_aqara_fp400
