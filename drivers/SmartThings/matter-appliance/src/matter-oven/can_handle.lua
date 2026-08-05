-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_oven_device(opts, driver, device)
  local common_utils = require "common-utils"
  local OVEN_DEVICE_ID = 0x007B
  local oven_eps = common_utils.get_endpoints_for_dt(device, OVEN_DEVICE_ID)
  if #oven_eps > 0 then
    return true, require("matter-oven")
  end
  return false
end

return is_oven_device
