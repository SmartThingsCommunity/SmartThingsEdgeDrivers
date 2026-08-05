-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function gatorsystem_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "GatorSystem" and device:get_model() == "GSHW01" then
    return true, require("gatorsystem")
  end
  return false
end

return gatorsystem_can_handle
