-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

local function is_unmigrated_matter_lock_product(opts, driver, device)
  local device_lib = require "st.device"
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    return false
  end
  local is_migrated = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.migrated.NAME) or nil
  if device:supports_capability(capabilities.lockAlarm) then
    return false
  elseif device:supports_capability(capabilities.lockCodes) and is_migrated == true then
    return false
  else
    return true, require("unmigrated-matter-lock")
  end
end

return is_unmigrated_matter_lock_products