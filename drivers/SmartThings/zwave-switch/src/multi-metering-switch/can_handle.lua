-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local function can_handle_multi_metering_switch(opts, driver, device, ...)
  local fingerprints = require("multi-metering-switch.fingerprints")
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("multi-metering-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_multi_metering_switch
