-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local lock_utils = require("zwave_lock_utils")
  local slga_migrated = device:get_field(lock_utils.SLGA_MIGRATED) or false
  if slga_migrated then
    if opts.dispatcher_class == "ZwaveDispatcher" and cmd ~= nil and cmd.version ~= nil and cmd.version == 1 then
      local subdriver = require("zwave-alarm-v1-lock")
      return true, subdriver
    end
  end
  return false
end
