-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_multisensor_7(opts, self, device, ...)
  local MULTISENSOR_7_PRODUCT_ID = 0x0018
  if device.zwave_product_id == MULTISENSOR_7_PRODUCT_ID then
    return true, require("aeotec-multisensor.multisensor-7")
  end
  return false
end

return can_handle_multisensor_7
