-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local capabilities = require "st.capabilities"
  local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
    capabilities.lockCodes.migrated.NAME, false)
  if lock_codes_migrated then
    if opts.dispatcher_class == "ZwaveDispatcher" and cmd ~= nil and cmd.version ~= nil and cmd.version == 1 then
      local subdriver = require("zwave-alarm-v1-lock")
      return true, subdriver
    end
  end
  return false
end
