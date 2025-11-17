-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_fibaro_rgbw_controller(opts, driver, device, ...)
  return device:id_match(
    FIBARO_MFR_ID,
    FIBARO_RGBW_CONTROLLER_PROD_TYPE,
    {FIBARO_RGBW_CONTROLLER_PROD_ID_US, FIBARO_RGBW_CONTROLLER_PROD_ID_EU}
  )
end

return is_fibaro_rgbw_controller
