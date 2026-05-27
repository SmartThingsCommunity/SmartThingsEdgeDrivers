-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_new_matter_lock_products(opts, driver, device)
  local device_lib = require "st.device"
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    return false
  end
  local FINGERPRINTS = require("new-matter-lock.fingerprints")
  for _, p in ipairs(FINGERPRINTS) do
    if device.manufacturer_info.vendor_id == p[1] and
      device.manufacturer_info.product_id == p[2] then
        return true, require("new-matter-lock")
    end
  end
  return false
end

return is_new_matter_lock_products
