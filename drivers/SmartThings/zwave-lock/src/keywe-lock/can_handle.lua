-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_keywe_lock(opts, self, device, cmd, ...)
  local KEYWE_MFR = 0x037B
  if device.zwave_manufacturer_id == KEYWE_MFR then
    return true, require("keywe-lock")
  end
  return false
end

return can_handle_keywe_lock
