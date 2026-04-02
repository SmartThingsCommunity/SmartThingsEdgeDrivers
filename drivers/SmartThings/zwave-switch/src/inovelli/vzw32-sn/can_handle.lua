-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_VZW32_SN_PRODUCT_TYPE = 0x0017
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001

local function can_handle_vzw32_sn(opts, driver, device, ...)
  if device:id_match(
    INOVELLI_MANUFACTURER_ID,
    INOVELLI_VZW32_SN_PRODUCT_TYPE,
    INOVELLI_DIMMER_PRODUCT_ID
  ) then
    return true, require("inovelli.vzw32-sn")
  end
  return false
end

return can_handle_vzw32_sn
