return function(opts, driver, device, ...)
  local capabilities = require "st.capabilities"
  local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
    capabilities.lockCodes.migrated.NAME, false)
  if lock_codes_migrated then
    local subdriver = require("using-new-capabilities")
    return true, subdriver
  end
  return false
end