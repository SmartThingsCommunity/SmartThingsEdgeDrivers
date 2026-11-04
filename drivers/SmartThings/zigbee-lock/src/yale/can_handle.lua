-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local consts = require "lock_utils.constants"
  local slga_migrated = device:get_field(consts.DRIVER_STATE.SLGA_MIGRATED) or false
  local manufacturer = device:get_manufacturer()
  if slga_migrated and (manufacturer == "Yale" or manufacturer == "ASSA ABLOY iRevo") then
    return true, require("yale")
  end
  return false
end
