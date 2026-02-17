-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function ozom_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "ClimaxTechnology" then
    return true, require("ozom")
  end
  return false
end

return ozom_can_handle
