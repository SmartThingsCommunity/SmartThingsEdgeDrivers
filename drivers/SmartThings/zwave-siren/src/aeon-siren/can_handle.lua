-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aeon_siren(opts, driver, device, ...)
  local AEON_MFR = 0x0086
  local AEON_SIREN_PRODUCT_ID = 0x0050

  if device.zwave_manufacturer_id == AEON_MFR and device.zwave_product_id == AEON_SIREN_PRODUCT_ID then
    return true, require("aeon-siren")
  end
  return false
end

return can_handle_aeon_siren
