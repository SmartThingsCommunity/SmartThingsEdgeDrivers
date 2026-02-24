-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_schlage_lock(opts, self, device, cmd, ...)
  local SCHLAGE_MFR = 0x003B
  if device.zwave_manufacturer_id == SCHLAGE_MFR then
    return true, require("schlage-lock")
  end
  return false
end

return can_handle_schlage_lock
