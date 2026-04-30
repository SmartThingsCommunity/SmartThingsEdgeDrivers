-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.

local capabilities = require "st.capabilities"

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local power_consumption = {}

power_consumption.emit_power_consumption_report_event = function (device, value)
    -- powerConsumptionReport report interval
    local current_time = os.time()
    local last_time = device:get_field(LAST_REPORT_TIME) or 0
    local next_time = last_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
    if current_time < next_time then
        return
    end
    device:set_field(LAST_REPORT_TIME, current_time, { persist = true })
    local raw_value = value.value * 1000 -- 'Wh'

    local delta_energy = 0.0
    local current_power_consumption = device:get_latest_state('main', capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
    if current_power_consumption ~= nil then
        delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
    end
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
        energy = raw_value,
        deltaEnergy = delta_energy
    }))
end

return power_consumption