-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local KEYWE_MFR = 0x037B
  if device.zwave_manufacturer_id == KEYWE_MFR then
    local subdriver = require("using-new-capabilities.keywe-lock")
    return true, subdriver
  end
  return false
end