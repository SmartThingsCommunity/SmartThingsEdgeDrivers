-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function zenwithin_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "Zen Within" and device:get_model() == "Zen-01" then
    return true, require("zenwithin")
  end
  return false
end

return zenwithin_can_handle
