-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local lock_utils = require "lock_utils"

local function is_unmigrated_matter_lock_product(opts, driver, device)
  local lock_codes_copy_required = device:get_field(lock_utils.LOCK_CODES_COPY_REQUIRED) or nil
  if device:supports_capability(capabilities.lockAlarm) then
    return false
  elseif device:supports_capability(capabilities.lockCodes) and lock_codes_copy_required == true then
    return false
  else
    return true, require("unmigrated-matter-lock")
  end
end

return is_unmigrated_matter_lock_product
