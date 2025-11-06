-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


return function(opts, driver, device)
  local INOVELLI_FINGERPRINTS = {
    { mfr = "Inovelli", model = "VZM30-SN" },
    { mfr = "Inovelli", model = "VZM31-SN" },
    { mfr = "Inovelli", model = "VZM32-SN" }
  }
  for _, fp in ipairs(INOVELLI_FINGERPRINTS) do
    if device:get_manufacturer() == fp.mfr and device:get_model() == fp.model then
      local subdriver = require("inovelli")
      return true, subdriver
    end
  end
  return false
end
