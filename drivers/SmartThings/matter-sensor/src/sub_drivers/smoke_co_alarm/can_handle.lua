-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_matter_smoke_co_alarm(opts, driver, device)
    local SMOKE_CO_ALARM_DEVICE_TYPE_ID = 0x0076
    for _, ep in ipairs(device.endpoints) do
        for _, dt in ipairs(ep.device_types) do
            if dt.device_type_id == SMOKE_CO_ALARM_DEVICE_TYPE_ID then
                return true, require("sub_drivers.smoke_co_alarm")
            end
        end
    end

    return false
end

return is_matter_smoke_co_alarm
