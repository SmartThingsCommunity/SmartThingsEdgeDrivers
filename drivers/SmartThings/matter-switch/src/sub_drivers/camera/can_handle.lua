-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local device_lib = require "st.device"
  local fields = require "switch_utils.fields"
  local switch_utils = require "switch_utils.utils"
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    return true, require("sub_drivers.camera")
  end
  return false
end
