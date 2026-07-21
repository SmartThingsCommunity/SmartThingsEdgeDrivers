-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function shinasystem_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "ShinaSystem" and (device:get_model() == "FAM-300Z") then
    return true, require("shinasystem")
  end
  return false
end

return shinasystem_can_handle
