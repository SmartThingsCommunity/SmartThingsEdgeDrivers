-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local lock_utils = require("zwave_lock_utils")
  local slga_migrated = device:get_field(lock_utils.SLGA_MIGRATED)
  if slga_migrated then
    local SAMSUNG_MFR = 0x022E
    if device.zwave_manufacturer_id == SAMSUNG_MFR then
      local subdriver = require("samsung-lock")
      return true, subdriver
    end
  end
  return false
end
