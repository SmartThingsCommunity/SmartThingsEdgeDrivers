-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_utilitech_siren(opts, driver, device, ...)
  return device.zwave_manufacturer_id == UTILITECH_MFR and device.zwave_product_id == UTILITECH_SIREN_PRODUCT_ID
end

return can_handle_utilitech_siren
