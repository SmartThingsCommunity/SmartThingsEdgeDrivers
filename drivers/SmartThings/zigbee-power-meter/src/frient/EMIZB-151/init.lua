local zigbee_constants = require "st.zigbee.constants"
local capabilities = require "st.capabilities"

local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local utils = require "frient.utils"

local powerMeter_defaults = require "st.zigbee.defaults.powerMeter_defaults"
local energyMeter_defaults = require "st.zigbee.defaults.energyMeter_defaults"

local data_types = require "st.zigbee.data_types"
local log = require "log"
local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local SIMPLE_METERING_DEFAULT_DIVISOR = 1000

local ZIGBEE_POWER_METER_FINGERPRINTS = require("frient/EMIZB-151.fingerprints")

zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_MULTIPLIER_KEY = "_electrical_measurement_ac_voltage_multiplier"
zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_MULTIPLIER_KEY = "_electrical_measurement_ac_current_multiplier"
zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_DIVISOR_KEY = "_electrical_measurement_ac_voltage_divisor"
zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_DIVISOR_KEY = "_electrical_measurement_ac_current_divisor"

local CurrentSummationReceived = 0x0001

local ATTRIBUTES = {
    {
        cluster = SimpleMetering.ID,
        attribute = CurrentSummationReceived,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint48,
        reportable_change = 1
    },
    {
        cluster = SimpleMetering.ID,
        attribute = SimpleMetering.attributes.CurrentSummationDelivered.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint48,
        reportable_change = 1
    },
    {
        cluster = SimpleMetering.ID,
        attribute = SimpleMetering.attributes.InstantaneousDemand.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Int24,
        reportable_change = 1
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.ActivePower.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Int16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.ActivePowerPhB.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Int16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.ActivePowerPhC.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Int16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSVoltage.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSVoltagePhB.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSVoltagePhC.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSCurrent.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSCurrentPhB.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 5
    },
    {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSCurrentPhC.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 5
    }
}

local device_init = function(self, device)
    for _, attribute in ipairs(ATTRIBUTES) do
        device:add_configured_attribute(attribute)
        --device:add_monitored_attribute(attribute)
    end
end

local do_configure = function(self, device)
    device:refresh()
    device:configure()

    -- Divisor and multipler for PowerMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))

    -- Divisor and multipler for EnergyMeter
    device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
    device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
    device:send(ElectricalMeasurement.attributes.ACVoltageMultiplier:read(device))
    device:send(ElectricalMeasurement.attributes.ACVoltageDivisor:read(device))
    device:send(ElectricalMeasurement.attributes.ACCurrentMultiplier:read(device))
    device:send(ElectricalMeasurement.attributes.ACCurrentDivisor:read(device))
end

local instantaneous_demand_handler = function(driver, device, value, zb_rx)
    local raw_value = value.value
    --- demand = demand received * Multipler/Divisor
    local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
    local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or SIMPLE_METERING_DEFAULT_DIVISOR

    if divisor == 0 then
        log.warn_with({ hub_logs = true }, "Metering scale divisor is 0; using 1 to avoid division by zero")
        divisor = 1
    end

    raw_value = raw_value * multiplier / divisor * 1000

    -- The result is already in watts, no need to multiply by 1000
    device:emit_component_event(device.profile.components['main'], capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local current_summation_delivered_handler = function(driver, device, value, zb_rx)
    local raw_value = value.value

    -- Handle potential overflow values
    if raw_value < 0 or raw_value >= 0xFFFFFFFFFFFF then
        log.warn_with({ hub_logs = true }, "Invalid CurrentSummationDelivered value received; ignoring report")
        return
    end

    local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
    local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or SIMPLE_METERING_DEFAULT_DIVISOR

    if divisor == 0 then
        log.warn_with({ hub_logs = true }, "Metering scale divisor is 0; using 1 to avoid division by zero")
        divisor = 1
    end

    raw_value = raw_value * multiplier / divisor * 1000
    log.debug("CurrentSummationDelivered: raw=" .. tostring(value.value) .. ", multiplier=" .. tostring(multiplier) .. ", divisor=" .. tostring(divisor) .. ", final=" .. tostring(raw_value))
    device:emit_component_event(device.profile.components['main'], capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))

    local delta_energy = 0.0
    local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
    if current_power_consumption ~= nil then
        delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
    end

    local current_time = os.time()
    log.trace("current_time: "..current_time)
    local last_report_time = device:get_field(LAST_REPORT_TIME) or 0
    log.trace("last_report_time: "..last_report_time)
    local next_report_time = last_report_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
    log.trace("next_report_time: "..next_report_time)
    if current_time < next_report_time then
        log.trace("EXIT: ")
        return
    end

    device:emit_event_for_endpoint(
        zb_rx.address_header.src_endpoint.value,
        capabilities.powerConsumptionReport.powerConsumption({
            start = utils.epoch_to_iso8601(last_report_time),
            ["end"] = utils.epoch_to_iso8601(current_time - 1),
            deltaEnergy = delta_energy,
            energy = raw_value
        })
    )
    device:set_field(LAST_REPORT_TIME, current_time, { persist = true })
end

local current_summation_received_handler = function(driver, device, value, zb_rx)
    local raw_value = value.value

    -- Handle potential overflow values
    if raw_value < 0 or raw_value >= 0xFFFFFFFFFFFF then
        log.warn_with({ hub_logs = true }, "Invalid CurrentSummationReceived value received; ignoring report")
        return
    end

    local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
    local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or 1000

    if divisor == 0 then
        log.warn_with({ hub_logs = true }, "Metering scale divisor is 0; using 1 to avoid division by zero")
        divisor = 1
    end

    raw_value = raw_value * multiplier / divisor * 1000
    log.debug("CurrentSummationReceived: raw=" .. tostring(value.value) .. ", multiplier=" .. tostring(multiplier) .. ", divisor=" .. tostring(divisor) .. ", final=" .. tostring(raw_value))
    device:emit_component_event(device.profile.components['production'], capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))
end

local electrical_measurement_ac_voltage_multiplier_handler = function(driver, device, multiplier, zb_rx)
    local raw_value = multiplier.value
    log.debug("Setting AC voltage multiplier: " .. tostring(raw_value))
    device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_MULTIPLIER_KEY, raw_value, { persist = true })
end

local electrical_measurement_ac_voltage_divisor_handler = function(driver, device, divisor, zb_rx)
    local raw_value = divisor.value
    log.debug("Setting AC voltage divisor: " .. tostring(raw_value))
    device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_DIVISOR_KEY, raw_value, { persist = true })
end

local electrical_measurement_ac_current_multiplier_handler = function(driver, device, multiplier, zb_rx)
    local raw_value = multiplier.value
    log.debug("Setting AC current multiplier: " .. tostring(raw_value))
    device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_MULTIPLIER_KEY, raw_value, { persist = true })
end

local electrical_measurement_ac_current_divisor_handler = function(driver, device, divisor, zb_rx)
    local raw_value = divisor.value
    log.debug("Setting AC current divisor: " .. tostring(raw_value))
    device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_DIVISOR_KEY, raw_value, { persist = true })
end

local active_power_handler = function(component)
    local handler = function(driver, device, value, zb_rx)
        local raw_value = value.value
        -- By default emit raw value
        local multiplier = device:get_field(zigbee_constants.ELECTRICAL_MEASUREMENT_MULTIPLIER_KEY) or 1
        local divisor = device:get_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) or 1

        if divisor == 0 then
            log.warn_with({ hub_logs = true }, "Power scale divisor is 0; using 1 to avoid division by zero")
            divisor = 1
        end

        raw_value = raw_value * multiplier / divisor

        device:emit_component_event(device.profile.components[component], capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
    end

    return handler
end

local rms_voltage_handler = function(component)
    local handler = function(driver, device, value, zb_rx)
        local raw_value = value.value
        -- By default emit raw value
        local multiplier = device:get_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_MULTIPLIER_KEY) or 1
        local divisor = device:get_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_DIVISOR_KEY) or 1

        if divisor == 0 then
            log.warn_with({ hub_logs = true }, "Voltage scale divisor is 0; using 1 to avoid division by zero")
            divisor = 1
        end

        raw_value = raw_value * multiplier / divisor

        device:emit_component_event(device.profile.components[component], capabilities.voltageMeasurement.voltage({ value = raw_value, unit = "V" }))
    end

    return handler
end

local rms_current_handler = function(component)
    local handler = function(driver, device, value, zb_rx)
        local raw_value = value.value
        -- By default emit raw value
        local multiplier = device:get_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_MULTIPLIER_KEY) or 1
        local divisor = device:get_field(zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_DIVISOR_KEY) or 1

        if divisor == 0 then
            log.warn_with({ hub_logs = true }, "Current scale divisor is 0; using 1 to avoid division by zero")
            divisor = 1
        end

        raw_value = raw_value * multiplier / divisor

        device:emit_component_event(device.profile.components[component], capabilities.currentMeasurement.current({ value = raw_value, unit = "A" }))
    end

    return handler
end

local function simple_metering_divisor_handler(driver, device, divisor, zb_rx)
    local header = zb_rx.body and zb_rx.body.zcl_header
    local is_mfg_specific = header and header.frame_ctrl:is_mfg_specific_set()
    local has_expected_type = divisor ~= nil and divisor.ID == data_types.Uint24.ID

    if is_mfg_specific or not has_expected_type then
        log.debug_with(
                { hub_logs = true },
                string.format(
                        "Ignoring divisor report (mfg_specific=%s, type=%s, value=%s)",
                        tostring(is_mfg_specific),
                        has_expected_type and "Uint24" or tostring(divisor and divisor.NAME or "nil"),
                        tostring(divisor and divisor.value)
                )
        )
        return
    end

    local raw_value = divisor.value
    log.info_with({ hub_logs = true }, "Received Simple Metering divisor: " .. tostring(raw_value))

    if raw_value == 0 then
        log.warn_with({ hub_logs = true }, "Simple metering divisor is 0; using 1 to avoid division by zero")
        raw_value = 1
    end

    device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, raw_value, { persist = true })
end

local function simple_metering_multiplier_handler(driver, device, multiplier, zb_rx)
    if not zb_rx.body.zcl_header.frame_ctrl:is_mfg_specific_set() then
        local raw_value = multiplier.value
        log.info_with({ hub_logs = true }, "Received Simple Metering multiplier: " .. tostring(raw_value))
        device:set_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY, raw_value, { persist = true })
    end
end

local frient_emi = {
    NAME = "EMIZB-151",
    lifecycle_handlers = {
        init = device_init,
        doConfigure = do_configure
    },
    zigbee_handlers = {
        cluster = {
        },
        attr = {
            [SimpleMetering.ID] = {
                [CurrentSummationReceived] = current_summation_received_handler,
                [SimpleMetering.attributes.CurrentSummationDelivered.ID] = current_summation_delivered_handler,
                [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler,
                [SimpleMetering.attributes.Multiplier.ID] = simple_metering_multiplier_handler,
                [SimpleMetering.attributes.Divisor.ID] = simple_metering_divisor_handler
            },
            [ElectricalMeasurement.ID] = {
                --[ElectricalMeasurement.attributes.ACPowerDivisor.ID] = powerMeter_defaults.electrical_measurement_divisor_handler,
                --[ElectricalMeasurement.attributes.ACPowerMultiplier.ID] = powerMeter_defaults.electrical_measurement_multiplier_handler,
                [ElectricalMeasurement.attributes.ACVoltageDivisor.ID] = electrical_measurement_ac_voltage_divisor_handler,
                [ElectricalMeasurement.attributes.ACVoltageMultiplier.ID] = electrical_measurement_ac_voltage_multiplier_handler,
                [ElectricalMeasurement.attributes.ACCurrentDivisor.ID] = electrical_measurement_ac_current_divisor_handler,
                [ElectricalMeasurement.attributes.ACCurrentMultiplier.ID] = electrical_measurement_ac_current_multiplier_handler,
                [ElectricalMeasurement.attributes.ActivePower.ID] = active_power_handler("phaseA"),
                [ElectricalMeasurement.attributes.RMSVoltage.ID] = rms_voltage_handler("phaseA"),
                [ElectricalMeasurement.attributes.RMSCurrent.ID] = rms_current_handler("phaseA"),
                [ElectricalMeasurement.attributes.ActivePowerPhB.ID] = active_power_handler("phaseB"),
                [ElectricalMeasurement.attributes.RMSVoltagePhB.ID] = rms_voltage_handler("phaseB"),
                [ElectricalMeasurement.attributes.RMSCurrentPhB.ID] = rms_current_handler("phaseB"),
                [ElectricalMeasurement.attributes.ActivePowerPhC.ID] = active_power_handler("phaseC"),
                [ElectricalMeasurement.attributes.RMSVoltagePhC.ID] = rms_voltage_handler("phaseC"),
                [ElectricalMeasurement.attributes.RMSCurrentPhC.ID] = rms_current_handler("phaseC")
            }
        }
    },
    can_handle = require("frient/EMIZB-151.can_handle")
}

return frient_emi