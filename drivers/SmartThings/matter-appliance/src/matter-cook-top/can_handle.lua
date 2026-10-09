-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_cook_top_device(opts, driver, device, ...)
  local common_utils = require "common-utils"
  local COOK_TOP_DEVICE_TYPE_ID = 0x0078
  local OVEN_DEVICE_ID = 0x007B

  local cook_top_eps = common_utils.get_endpoints_for_dt(device, COOK_TOP_DEVICE_TYPE_ID)
  local oven_eps = common_utils.get_endpoints_for_dt(device, OVEN_DEVICE_ID)
  -- we want to skip lifecycle events in cases where the device is an oven with a composed cook-top device
  if (#oven_eps > 0) and opts.dispatcher_class == "DeviceLifecycleDispatcher" then
    return false
  end
  if #cook_top_eps > 0 then
    return true, require("matter-cook-top")
  end
  return false
end

return is_cook_top_device
