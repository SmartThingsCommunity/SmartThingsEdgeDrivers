-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_fibaro_rgbw_controller(opts, driver, device, ...)
  local FIBARO_MFR_ID = 0x010F
  local FIBARO_RGBW_CONTROLLER_PROD_TYPE = 0x0900
  local FIBARO_RGBW_CONTROLLER_PROD_ID_US = 0x2000
  local FIBARO_RGBW_CONTROLLER_PROD_ID_EU = 0x1000

  if device:id_match(
    FIBARO_MFR_ID,
    FIBARO_RGBW_CONTROLLER_PROD_TYPE,
    {FIBARO_RGBW_CONTROLLER_PROD_ID_US, FIBARO_RGBW_CONTROLLER_PROD_ID_EU}
  ) then
    return true, require("fibaro-rgbw-controller")
  end
  return false
end

return is_fibaro_rgbw_controller
