-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  local fingerprints = require("legacy-handlers.lock-without-codes.fingerprints")
  for _, fingerprint in ipairs(fingerprints) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("legacy-handlers.lock-without-codes")
      return true, subdriver
    end
  end
  return false
end
