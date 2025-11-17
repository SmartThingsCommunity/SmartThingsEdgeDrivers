-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_yale_siren(opts, self, device, ...)
  return device.zwave_manufacturer_id == YALE_MFR
end

return can_handle_yale_siren
