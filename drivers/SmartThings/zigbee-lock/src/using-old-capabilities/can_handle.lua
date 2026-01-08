-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local capabilities = require "st.capabilities"
  local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
    capabilities.lockCodes.migrated.NAME, false)
  if not lock_codes_migrated then
    local subdriver = require("using-old-capabilities")
    return true, subdriver
  end
  return false
end