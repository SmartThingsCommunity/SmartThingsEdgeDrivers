-- Copyright 2026 SmartThings
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local capabilities = require "st.capabilities"
  local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
    capabilities.lockCodes.migrated.NAME, false)
  if not lock_codes_migrated then return false end
  if device:get_manufacturer() == "SAMSUNG SDS" then
    local subdriver = require("samsungsds")
    return true, subdriver
  end
  return false
end
