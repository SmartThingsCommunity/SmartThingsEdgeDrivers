-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
local FINGERPRINTS = {
  { mfr = "LAISIAO", model = "yuba" },
  { mfr = "LAISIAO", model = "DG60GCM-04-2904W" },
}

  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("laisiao")
      return true, subdriver
    end
  end
  return false
end
