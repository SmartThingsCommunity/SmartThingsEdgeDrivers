-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_matter_air_quality_sensor(opts, driver, device)
    local fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"
    for _, ep in ipairs(device.endpoints) do
        for _, dt in ipairs(ep.device_types) do
            if dt.device_type_id == fields.AIR_QUALITY_SENSOR_DEVICE_TYPE_ID then
                return true, require("sub_drivers.air_quality_sensor")
            end
        end
    end

    return false
end

return is_matter_air_quality_sensor
