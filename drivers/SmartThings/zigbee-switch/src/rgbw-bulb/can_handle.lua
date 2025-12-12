-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local RGBW_BULB_FINGERPRINTS = require "rgbw-bulb.fingerprints"
  local can_handle = (RGBW_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("rgbw-bulb")
    return true, subdriver
  else
    return false
  end
end
