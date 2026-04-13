-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function roller_shade_can_handle(opts, driver, device, ...)
  if device:get_model() == "lumi.curtain.aq2" then
    return true, require("aqara.roller-shade")
  end
  return false
end

return roller_shade_can_handle
