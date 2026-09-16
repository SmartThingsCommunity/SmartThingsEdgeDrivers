-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Matches any device whose manufacturer/model is listed in aqara/fingerprints.lua, routing it to
-- the aqara sub-driver (and, in turn, its version / multi-switch sub-drivers).
return function(opts, driver, device)
  local FINGERPRINTS = require("aqara.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("aqara")
      return true, subdriver
    end
  end
  return false
end
