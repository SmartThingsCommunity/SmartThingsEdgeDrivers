-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local WINTEC_VENDOR_ID = 0x1578
local WINTEC_PRODUCT_ID = 0x1A01

return function(opts, driver, device)
  local device_lib = require "st.device"
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    return false
  end
  if device.manufacturer_info.vendor_id == WINTEC_VENDOR_ID and
    device.manufacturer_info.product_id == WINTEC_PRODUCT_ID then
    return true, require("sub_drivers.wintec")
  end
  return false
end
