-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local WHITE_COLOR_TEMP_BULB_FINGERPRINTS = require "white-color-temp-bulb.fingerprints"
  local can_handle = (WHITE_COLOR_TEMP_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("white-color-temp-bulb")
    return true, subdriver
  else
    return false
  end
end
