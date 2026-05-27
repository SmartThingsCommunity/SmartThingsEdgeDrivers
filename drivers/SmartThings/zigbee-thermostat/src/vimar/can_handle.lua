-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local vimar_thermostat_can_handle = function(opts, driver, device)
  local VIMAR_THERMOSTAT_FINGERPRINT = {
    mfr = "Vimar",
    model = "WheelThermostat_v1.0"
  }

  if device:get_manufacturer() == VIMAR_THERMOSTAT_FINGERPRINT.mfr and
    device:get_model() == VIMAR_THERMOSTAT_FINGERPRINT.model then
      return true, require("vimar")
  end
  return false
end

return vimar_thermostat_can_handle
