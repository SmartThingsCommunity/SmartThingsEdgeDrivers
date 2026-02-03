-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local device_lib = require "st.device"
  local fields = require "switch_utils.fields"
  local switch_utils = require "switch_utils.utils"
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    device = device:get_parent_device()
  end
  if #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.WINDOW_COVERING) > 0 or
    #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.CLOSURE) > 0 then
    return true, require("sub_drivers.closures")
  end
  return false
end
