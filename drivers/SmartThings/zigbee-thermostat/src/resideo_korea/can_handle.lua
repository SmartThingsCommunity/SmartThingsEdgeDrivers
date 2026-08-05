-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function resideo_korea_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Resideo Korea" and device:get_model() == "DT300ST-M000" then
    return true, require("resideo_korea")
  end
  return false
end

return resideo_korea_can_handle
