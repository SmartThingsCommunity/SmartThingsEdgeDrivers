-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_door_window_sensor_2(opts, driver, device, cmd, ...)
  local FINGERPRINTS = require("fibaro-door-window-sensor.fibaro-door-window-sensor-2.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("fibaro-door-window-sensor.fibaro-door-window-sensor-2")
    end
  end
  return false
end

return can_handle_fibaro_door_window_sensor_2
