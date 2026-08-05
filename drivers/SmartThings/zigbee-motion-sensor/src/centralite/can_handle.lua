-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function centralite_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "CentraLite" then
    return true, require("centralite")
  end
  return false
end

return centralite_can_handle
