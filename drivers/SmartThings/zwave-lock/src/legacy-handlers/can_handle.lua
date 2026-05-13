-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local lock_utils = require("zwave_lock_utils")
  local slga_migrated = device:get_field(lock_utils.SLGA_MIGRATED)
  if not slga_migrated then
    local subdriver = require("legacy-handlers")
    return true, subdriver
  end
  return false
end
