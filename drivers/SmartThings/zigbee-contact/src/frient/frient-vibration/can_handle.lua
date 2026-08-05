-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local FRIENT_DEVICE_FINGERPRINTS = {
  { mfr = "frient A/S", model = "WISZB-137", },
}

return function(opts, driver, device, ...)
  for _, fingerprint in ipairs(FRIENT_DEVICE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("frient.frient-vibration")
    end
  end
  return false
end
