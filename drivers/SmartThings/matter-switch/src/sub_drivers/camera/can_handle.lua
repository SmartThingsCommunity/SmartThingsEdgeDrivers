-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local device_lib = require "st.device"
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    local version = require "version"
    if version.rpc >= 10 and version.api >= 16 then
      local fields = require "switch_utils.fields"
      local switch_utils = require "switch_utils.utils"
      if #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.CAMERA) > 0 then
        return true, require("sub_drivers.camera")
      end
    end
  end
  return false
end
