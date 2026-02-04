-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_zigbee_plugin_motion_sensor = function(opts, driver, device)
  local FINGERPRINTS = require("zigbee-plugin-motion-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true, require("zigbee-plugin-motion-sensor")
    end
  end
  return false
end

return is_zigbee_plugin_motion_sensor
