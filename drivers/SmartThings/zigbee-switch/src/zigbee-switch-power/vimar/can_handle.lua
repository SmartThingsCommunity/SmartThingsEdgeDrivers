-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


return function(opts, driver, device)
  local VIMAR_FINGERPRINTS = {
    { mfr = "Vimar", model = "Mains_Power_Outlet_v1.0" }
  }
  for _, fingerprint in ipairs(VIMAR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("zigbee-switch-power.vimar")
    end
  end
  return false
end
