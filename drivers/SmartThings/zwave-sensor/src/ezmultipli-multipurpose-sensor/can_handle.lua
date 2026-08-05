-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_ezmultipli_multipurpose_sensor(opts, driver, device, ...)
  local EZMULTIPLI_MULTIPURPOSE_SENSOR_FINGERPRINTS = { manufacturerId = 0x001E, productType = 0x0004, productId = 0x0001 }
  if device:id_match(EZMULTIPLI_MULTIPURPOSE_SENSOR_FINGERPRINTS.manufacturerId,
      EZMULTIPLI_MULTIPURPOSE_SENSOR_FINGERPRINTS.productType,
      EZMULTIPLI_MULTIPURPOSE_SENSOR_FINGERPRINTS.productId) then
    local subdriver = require("ezmultipli-multipurpose-sensor")
    return true, subdriver
  end
  return false
end

return can_handle_ezmultipli_multipurpose_sensor
