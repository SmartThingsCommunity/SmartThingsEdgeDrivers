-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_utilitech_siren(opts, driver, device, ...)
  local UTILITECH_MFR = 0x0060
  local UTILITECH_SIREN_PRODUCT_ID = 0x0001
  if device.zwave_manufacturer_id == UTILITECH_MFR and device.zwave_product_id == UTILITECH_SIREN_PRODUCT_ID then
    return true, require("utilitech-siren")
  end
  return false
end

return can_handle_utilitech_siren
