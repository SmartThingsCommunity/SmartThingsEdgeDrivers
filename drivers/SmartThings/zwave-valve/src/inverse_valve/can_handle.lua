-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function inverse_valve_can_handle(opts, driver, device, ...)
  if device.zwave_manufacturer_id == 0x0084 or device.zwave_manufacturer_id == 0x027A then
    return true, require("inverse_valve")
  end
  return false
end

return inverse_valve_can_handle
