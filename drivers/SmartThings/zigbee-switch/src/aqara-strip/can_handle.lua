-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local FINGERPRINTS = require("aqara-strip.fingerprints")

return function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("aqara-strip")
      return true, subdriver
    end
  end
  return false
end
