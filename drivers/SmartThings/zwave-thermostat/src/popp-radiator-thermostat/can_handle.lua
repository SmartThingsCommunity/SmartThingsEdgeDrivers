-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_popp_radiator_thermostat(opts, driver, device, ...)
  local POPP_THERMOSTAT_FINGERPRINT = {mfr = 0x0002, prod = 0x0115, model = 0xA010}

  if device:id_match(POPP_THERMOSTAT_FINGERPRINT.mfr, POPP_THERMOSTAT_FINGERPRINT.prod, POPP_THERMOSTAT_FINGERPRINT.model) then
    return true, require "popp-radiator-thermostat"
  else
    return false
  end
end

return can_handle_popp_radiator_thermostat
