-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_thingsone_presence_sensor(opts, driver, device)
  local sensor_utils = require "sensor_utils.utils"
  if sensor_utils.get_product_override_field(device, "is_thingsone_presence_sensor") then
    return true, require("sub_drivers.thingsone_presence_sensor")
  end
  return false
end

return is_thingsone_presence_sensor
