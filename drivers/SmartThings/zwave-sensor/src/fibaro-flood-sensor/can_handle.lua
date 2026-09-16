-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_flood_sensor(opts, driver, device, ...)
    local FIBARO_MFR_ID = 0x010F
    local FIBARO_FLOOD_PROD_TYPES = { 0x0000, 0x0B00 }
    if device:id_match(FIBARO_MFR_ID, FIBARO_FLOOD_PROD_TYPES, nil) then
        local subdriver = require("fibaro-flood-sensor")
        return true, subdriver
    end
    return false
end

return can_handle_fibaro_flood_sensor
