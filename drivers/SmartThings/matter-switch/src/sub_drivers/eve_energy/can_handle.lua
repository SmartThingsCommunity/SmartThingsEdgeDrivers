-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

return function(opts, driver, device)
  local EVE_PRIVATE_CLUSTER_ID = 0x130AFC01
  -- this sub driver loads for devices that:
  -- 1. Contain the Eve Private Cluster (0x130AFC01)
  -- 2. Do NOT have the Standard Electrical Sensor device type
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
    #device:get_endpoints(EVE_PRIVATE_CLUSTER_ID) > 0 and
    #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.ELECTRICAL_SENSOR) == 0 then
    return true, require("sub_drivers.eve_energy")
  end
  return false
end
