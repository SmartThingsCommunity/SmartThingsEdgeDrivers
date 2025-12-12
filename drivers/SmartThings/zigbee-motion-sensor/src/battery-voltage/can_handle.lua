-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local can_handle_battery_voltage = function(opts, driver, device, ...)
  local FINGERPRINTS = require("battery-voltage.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("battery-voltage")
    end
  end
  return false
end

return can_handle_battery_voltage
