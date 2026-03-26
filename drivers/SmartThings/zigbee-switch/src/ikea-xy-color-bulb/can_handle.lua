-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


return function(opts, driver, device)
  local IKEA_XY_COLOR_BULB_FINGERPRINTS = {
    ["IKEA of Sweden"] = {
      ["TRADFRI bulb E27 CWS opal 600lm"] = true,
      ["TRADFRI bulb E26 CWS opal 600lm"] = true
    }
  }
  local res = (IKEA_XY_COLOR_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if res then
    return res, require("ikea-xy-color-bulb")
  end
  return res
end
