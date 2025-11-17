-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local vimar_thermostat_can_handle = function(opts, driver, device)
  return device:get_manufacturer() == VIMAR_THERMOSTAT_FINGERPRINT.mfr and
      device:get_model() == VIMAR_THERMOSTAT_FINGERPRINT.model
end

return vimar_thermostat_can_handle
