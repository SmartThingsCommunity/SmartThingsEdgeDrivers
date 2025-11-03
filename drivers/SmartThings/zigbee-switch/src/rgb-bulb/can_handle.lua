-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
local RGB_BULB_FINGERPRINTS = {
  ["OSRAM"] = {
    ["Gardenspot RGB"] = true,
    ["LIGHTIFY Gardenspot RGB"] = true
  },
  ["LEDVANCE"] = {
    ["Outdoor Accent RGB"] = true
  }
}


  local can_handle = (RGB_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("rgb-bulb")
    return true, subdriver
  else
    return false
  end
end
