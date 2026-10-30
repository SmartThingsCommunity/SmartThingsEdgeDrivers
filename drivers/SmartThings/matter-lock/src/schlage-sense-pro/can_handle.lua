-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local constants = require "schlage-sense-pro.constants"

--- Matcher for Schlage Sense Pro (Aliro) UWB Door Lock.
---
--- Supports both initial onboarding and OTA driver updates for previously onboarded locks.
--- [PLACEHOLDER - OPTIONAL / VERIFICATION FOR ALLEGION]:
--- Matches Allegion Vendor ID (0x1236) with either the known Schlage Sense Pro Product ID (0x3800)
--- or the presence of the custom UWB cluster.
local function is_schlage_sense_pro(opts, driver, device)
  if device.manufacturer_info and device.manufacturer_info.vendor_id == constants.SCHLAGE_VENDOR_ID then
    if device.manufacturer_info.product_id == constants.SCHLAGE_SENSE_PRO_PRODUCT_ID or
       #device:get_endpoints(constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID) > 0 then
      return true, require("schlage-sense-pro")
    end
  end
  return false
end

return is_schlage_sense_pro
