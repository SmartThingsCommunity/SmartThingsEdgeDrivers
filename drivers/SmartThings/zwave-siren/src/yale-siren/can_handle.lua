-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_yale_siren(opts, self, device, ...)
  local YALE_MFR = 0x0129
  if device.zwave_manufacturer_id == YALE_MFR then
    return true, require("yale-siren")
  end
  return false
end

return can_handle_yale_siren
