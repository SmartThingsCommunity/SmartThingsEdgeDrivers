-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local DURAGREEN_BULB_FINGERPRINTS = {
    ["DURAGREEN"] = {
      ["DG-CW-02"] = true,
      ["DG-CW-01"] = true,
      ["DG-CCT-01"] = true
    },
  }
  local res = (DURAGREEN_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()] or false
  if res then
    return res, require("white-color-temp-bulb.duragreen")
  else
    return res
  end
end
