-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT = {
  {mfr = "Aurora", model = "DoubleSocket50AU"}
}

return function(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-dual-metering-switch")
      return true, subdriver
    end
  end
  return false
end
