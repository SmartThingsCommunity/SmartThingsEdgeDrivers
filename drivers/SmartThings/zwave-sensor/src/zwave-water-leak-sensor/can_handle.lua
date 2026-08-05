-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_water_leak_sensor(opts, driver, device, ...)
  local FINGERPRINTS = require("zwave-water-leak-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zwave-water-leak-sensor")
      return true, subdriver
    end
  end
  return false
end

return can_handle_water_leak_sensor
