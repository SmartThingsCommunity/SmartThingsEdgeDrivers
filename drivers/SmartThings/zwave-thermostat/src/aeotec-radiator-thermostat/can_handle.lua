-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_aeotec_radiator_thermostat(opts, driver, device, ...)
    local AEOTEC_THERMOSTAT_FINGERPRINT = {mfr = 0x0371, prod = 0x0002, model = 0x0015}

    if device:id_match(AEOTEC_THERMOSTAT_FINGERPRINT.mfr, AEOTEC_THERMOSTAT_FINGERPRINT.prod, AEOTEC_THERMOSTAT_FINGERPRINT.model) then
        return true, require "aeotec-radiator-thermostat"
    else
        return false
    end
end

return can_handle_aeotec_radiator_thermostat
