-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

return function(opts, driver, device)
  local EVE_MANUFACTURER_ID = 0x130A
  -- this sub driver does NOT support child devices, and ONLY supports Eve devices
  -- that do NOT support the Electrical Sensor device type
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
    device.manufacturer_info.vendor_id == EVE_MANUFACTURER_ID and
    #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.ELECTRICAL_SENSOR) == 0 then
    return true, require("sub_drivers.eve_energy")
  end
  return false
end
