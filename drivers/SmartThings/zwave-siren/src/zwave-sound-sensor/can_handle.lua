-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zwave_sound_sensor(opts, driver, device, ...)
  local FINGERPRINTS = require("zwave-sound-sensor.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("zwave-sound-sensor")
    end
  end
  return false
end

return can_handle_zwave_sound_sensor
