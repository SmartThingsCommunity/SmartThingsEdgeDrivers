-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local capabilities = require "st.capabilities"
  local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
    capabilities.lockCodes.migrated.NAME, false)
  if lock_codes_migrated then
    local SAMSUNG_MFR = 0x022E
    if device.zwave_manufacturer_id == SAMSUNG_MFR then
      local subdriver = require("samsung-lock")
      return true, subdriver
    end
  end
  return false
end
