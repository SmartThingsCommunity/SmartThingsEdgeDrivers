-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local fingerprints = require("ecolink-switch.fingerprints")

local function can_handle_ecolink(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("ecolink-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_ecolink