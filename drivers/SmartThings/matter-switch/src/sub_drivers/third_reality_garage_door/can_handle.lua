-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"

return function(opts, driver, device)
  local THIRD_REALITY_GARAGE_DOOR_FINGERPRINT = { vendor_id = 0x1407, product_id = 0x1098 }
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
    device.manufacturer_info.vendor_id == THIRD_REALITY_GARAGE_DOOR_FINGERPRINT.vendor_id and
    device.manufacturer_info.product_id == THIRD_REALITY_GARAGE_DOOR_FINGERPRINT.product_id then
    return true, require("sub_drivers.third_reality_garage_door")
  end
  return false
end
