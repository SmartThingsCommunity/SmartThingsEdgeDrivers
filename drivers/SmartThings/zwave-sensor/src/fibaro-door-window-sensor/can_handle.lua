-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_door_window_sensor(opts, driver, device, ...)
  local FINGERPRINTS = require("fibaro-door-window-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.prod, fingerprint.productId) then
      local subdriver = require("fibaro-door-window-sensor")
      return true, subdriver
    end
  end
  return false
end

return can_handle_fibaro_door_window_sensor
