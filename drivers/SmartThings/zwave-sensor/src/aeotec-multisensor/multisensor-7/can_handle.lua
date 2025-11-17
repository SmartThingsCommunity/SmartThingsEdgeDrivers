-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_multisensor_7(opts, self, device, ...)
  return device.zwave_product_id == MULTISENSOR_7_PRODUCT_ID
end

return can_handle_multisensor_7
