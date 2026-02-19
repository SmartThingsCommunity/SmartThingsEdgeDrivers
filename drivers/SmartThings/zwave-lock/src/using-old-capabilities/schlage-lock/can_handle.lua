-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local SCHLAGE_MFR = 0x003B
  if device.zwave_manufacturer_id == SCHLAGE_MFR then
    local subdriver = require("using-old-capabilities.schlage-lock")
    return true, subdriver
  end
  return false
end