-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local consts = require("lock_utils.constants")
  local slga_migrated = device:get_field(consts.DRIVER_STATE.SLGA_MIGRATED)
  if slga_migrated then
    local SCHLAGE_MFR = 0x003B
    if device.zwave_manufacturer_id == SCHLAGE_MFR then
      local subdriver = require("schlage-lock")
      return true, subdriver
    end
  end
  return false
end
