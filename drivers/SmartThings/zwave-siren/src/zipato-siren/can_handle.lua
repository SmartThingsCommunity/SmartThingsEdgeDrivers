-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zipato_siren(opts, driver, device, ...)
  local ZIPATO_MFR = 0x0131
  if device.zwave_manufacturer_id == ZIPATO_MFR then
    return true, require("zipato-siren")
  end
  return false
end

return can_handle_zipato_siren
