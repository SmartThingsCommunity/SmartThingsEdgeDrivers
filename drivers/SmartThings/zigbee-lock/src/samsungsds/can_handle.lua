-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function samsungsds_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "SAMSUNG SDS" then
    return true, require("samsungsds")
  end
  return false
end

return samsungsds_can_handle
