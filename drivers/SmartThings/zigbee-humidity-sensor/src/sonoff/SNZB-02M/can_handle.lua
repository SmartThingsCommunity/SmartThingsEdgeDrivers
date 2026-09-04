-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, ...)
  if device:get_model() == "SNZB-02M" then
    return true, require("sonoff.SNZB-02M")
  end

  return false
end

return can_handle
