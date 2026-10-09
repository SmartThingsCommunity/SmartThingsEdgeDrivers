-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function screen_innovations_can_handle(opts, driver, device, ...)
  if device:get_model() == "WM25/L-Z" then
    return true, require("screen-innovations")
  end
  return false
end

return screen_innovations_can_handle
