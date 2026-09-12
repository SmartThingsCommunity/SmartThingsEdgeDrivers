-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device)
  if device:get_manufacturer() == "SONOFF" and device:get_model() == "TRV-ZBT" then
    return true, require("sonoff")
  end

  return false
end

return can_handle
