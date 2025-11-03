-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


return function(opts, driver, device)
  local INOVELLI_VZM32_SN_FINGERPRINTS = {
    { mfr = "Inovelli", model = "VZM32-SN" },
  }
  for _, fp in ipairs(INOVELLI_VZM32_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fp.mfr and device:get_model() == fp.model then
      local sub_driver = require("inovelli.vzm32-sn")
      return true, sub_driver
    end
  end
  return false
end
