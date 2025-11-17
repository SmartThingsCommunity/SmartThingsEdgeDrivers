-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aeon_siren(opts, driver, device, ...)
  return device.zwave_manufacturer_id == AEON_MFR and device.zwave_product_id == AEON_SIREN_PRODUCT_ID
end

return can_handle_aeon_siren
