-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local consts = require "lock_utils.constants"
  local slga_migrated = device:get_field(consts.DRIVER_STATE.SLGA_MIGRATED) or false
  if not slga_migrated then
    local subdriver = require("legacy-handlers")
    return true, subdriver
  end
  return false
end
