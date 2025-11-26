-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31SN_PRODUCT_TYPE = 0x0001
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001

local function can_handle_lzw31sn(opts, driver, device, ...)
  if device:id_match(
    INOVELLI_MANUFACTURER_ID,
    INOVELLI_LZW31SN_PRODUCT_TYPE,
    INOVELLI_DIMMER_PRODUCT_ID
  ) then
    return true, require("inovelli.lzw31-sn")
  end
  return false
end

return can_handle_lzw31sn
