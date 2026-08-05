-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function compacta_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Compacta" then
    return true, require("compacta")
  end
  return false
end

return compacta_can_handle
