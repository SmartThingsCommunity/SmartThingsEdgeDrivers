-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_thermostat_heating_battery(opts, driver, device, cmd, ...)
    local DANFOSS_LC13_THERMOSTAT_FINGERPRINTS = require "thermostat-heating-battery.fingerprints"
    for _, fingerprint in ipairs(DANFOSS_LC13_THERMOSTAT_FINGERPRINTS) do
        if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
            return true, require "thermostat-heating-battery"
        end
    end

    return false
end

return can_handle_thermostat_heating_battery
