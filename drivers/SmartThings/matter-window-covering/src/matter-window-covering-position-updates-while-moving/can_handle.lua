-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_matter_window_covering_position_updates_while_moving(opts, driver, device)
  local device_lib = require "st.device"
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    return false
  end
  local FINGERPRINTS = require("matter-window-covering-position-updates-while-moving.fingerprints")
  for i, v in ipairs(FINGERPRINTS) do
    if device.manufacturer_info.vendor_id == v[1] and
       device.manufacturer_info.product_id == v[2] then
      return true, require("matter-window-covering-position-updates-while-moving")
    end
  end
  return false
end

return is_matter_window_covering_position_updates_while_moving
