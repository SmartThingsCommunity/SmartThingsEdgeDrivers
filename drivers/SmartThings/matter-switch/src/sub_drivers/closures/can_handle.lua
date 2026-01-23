-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local fields = require "switch_utils.fields"
  local switch_utils = require "switch_utils.utils"
  if #switch_utils.get_endpoints_by_device_type(device:get_parent_device() or device, fields.DEVICE_TYPE_ID.CLOSURE) > 0 or
    #switch_utils.get_endpoints_by_device_type(device:get_parent_device() or device, fields.DEVICE_TYPE_ID.WINDOW_COVERING) > 0 then
    return true, require("sub_drivers.closures")
  end
  return false
end
