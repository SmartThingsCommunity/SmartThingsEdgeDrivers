-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_bad_yale_lock_models = function(opts, driver, device)
  local FINGERPRINTS = require("yale.yale-bad-battery-reporter.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true, require("yale.yale-bad-battery-reporter")
      end
  end
  return false
end

return is_bad_yale_lock_models
