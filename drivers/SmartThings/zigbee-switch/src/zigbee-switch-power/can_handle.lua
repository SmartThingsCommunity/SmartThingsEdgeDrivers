-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local SWITCH_POWER_FINGERPRINTS = require "zigbee-switch-power.fingerprints"
  for _, fingerprint in ipairs(SWITCH_POWER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-switch-power")
      return true, subdriver
    end
  end
  return false
end
