-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_multisensor_6(opts, self, device, ...)
local MULTISENSOR_6_PRODUCT_ID = 0x0064
  if device.zwave_product_id == MULTISENSOR_6_PRODUCT_ID then
    return true, require("aeotec-multisensor.multisensor-6")
  end
  return false
end
return can_handle_multisensor_6
