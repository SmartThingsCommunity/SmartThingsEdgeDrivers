-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local fingerprints = require("fibaro-double-switch.fingerprints")

local function can_handle_fibaro_double_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-double-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_fibaro_double_switch