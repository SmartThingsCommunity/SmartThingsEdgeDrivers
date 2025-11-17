-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_samsung_lock(opts, self, device, cmd, ...)
  return device.zwave_manufacturer_id == SAMSUNG_MFR
end

return can_handle_samsung_lock
