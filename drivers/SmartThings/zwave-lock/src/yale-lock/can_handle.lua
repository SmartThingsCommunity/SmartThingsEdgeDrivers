-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local consts = require("lock_utils.constants")
  local slga_migrated = device:get_field(consts.DRIVER_STATE.SLGA_MIGRATED)
  if slga_migrated and device.zwave_manufacturer_id == require("yale-lock.admin").MANUFACTURER_ID then
    local subdriver = require("yale-lock")
    return true, subdriver
  end
  return false
end
