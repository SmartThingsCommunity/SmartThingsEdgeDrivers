-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function yale_can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == "ASSA ABLOY iRevo" or device:get_manufacturer() == "Yale" then
    return true, require("yale")
  end
  return false
end

return yale_can_handle
