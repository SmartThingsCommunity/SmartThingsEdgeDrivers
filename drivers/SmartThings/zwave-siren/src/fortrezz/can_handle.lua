-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fortrezz_siren(opts, self, device, ...)
  if device.zwave_manufacturer_id == 0x0084 and
    device.zwave_product_type == 0x0313 and
    device.zwave_product_id == 0x010B then
      return true, require("fortrezz")
    end
    return false
end

return can_handle_fortrezz_siren
