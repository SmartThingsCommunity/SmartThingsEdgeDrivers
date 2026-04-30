-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local fingerprints = require("using-old-capabilities.yale.yale-bad-battery-reporter.fingerprints")
  for _, fingerprint in ipairs(fingerprints) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
        local subdriver = require("using-old-capabilities.yale.yale-bad-battery-reporter")
        return true, subdriver
      end
  end
  return false
end
