-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_samsung_lock(opts, self, device, cmd, ...)
  local SAMSUNG_MFR = 0x022E
  if device.zwave_manufacturer_id == SAMSUNG_MFR then
    return true, require("samsung-lock")
  end
  return false
end

return can_handle_samsung_lock
