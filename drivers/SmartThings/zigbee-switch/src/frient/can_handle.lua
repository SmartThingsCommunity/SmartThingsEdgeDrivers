-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Function to determine if the driver can handle this device
return function(opts, driver, device, ...)
  local FRIENT_SMART_PLUG_FINGERPRINTS = require("frient.fingerprints")
  for _, fingerprint in ipairs(FRIENT_SMART_PLUG_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("frient")
      return true, subdriver
    end
  end
  return false
end
