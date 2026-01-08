-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local switch_utils = require "switch_utils.utils"
  local sensor_fields = require "sub_drivers.sensor.switch_sensor_utils.fields"
  device = device:get_parent_device() or device
  for device_type_id, _ in ipairs(sensor_fields.DEVICE_TYPE_PROFILE_MAP) do
    if #switch_utils.get_endpoints_by_device_type(device, device_type_id) > 0 then
      return true, require("sub_drivers.sensor")
    end
  end
  return false
end
