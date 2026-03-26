-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  device.log.info_with({ hub_logs = true }, string.format("camera driver - calling can_handle, network type: %s", device.network_type))
  local device_lib = require "st.device"
  local fields = require "switch_utils.fields"
  local switch_utils = require "switch_utils.utils"
  return true, require("sub_drivers.camera")
end
