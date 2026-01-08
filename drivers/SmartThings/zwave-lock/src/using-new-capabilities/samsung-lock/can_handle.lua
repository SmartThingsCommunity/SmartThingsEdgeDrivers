-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local SAMSUNG_MFR = 0x022E
  if device.zwave_manufacturer_id == SAMSUNG_MFR then
    local subdriver = require("using-new-capabilities.samsung-lock")
    return true, subdriver
  end
  return false
end