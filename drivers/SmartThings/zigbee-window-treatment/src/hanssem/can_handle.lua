-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function hanssem_can_handle(opts, driver, device, ...)
  if device:get_model() == "TS0601" then
    return true, require("hanssem")
  end
  return false
end

return hanssem_can_handle
