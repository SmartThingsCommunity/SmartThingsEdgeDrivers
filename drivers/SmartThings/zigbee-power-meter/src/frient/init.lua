-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zigbee_constants = require "st.zigbee.constants"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local PowerConfiguration = clusters.PowerConfiguration
local utils = require "frient.utils"

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

-- KK: local energyMeter_defaults = require "st.zigbee.defaults.energyMeter_defaults"

local data_types = require "st.zigbee.data_types"

local log = require "log"
local DEVELCO_MANUFACTURER_CODE = 0x1015
local SIMPLE_METERING_DEFAULT_DIVISOR = 1000

local ZIGBEE_POWER_METER_FINGERPRINTS = require("frient.fingerprints")

local ATTRIBUTES = {
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
    }
}

local is_frient_power_meter = function(opts, driver, device)
    for _, fingerprint in ipairs(ZIGBEE_POWER_METER_FINGERPRINTS) do
        if device:get_model() == fingerprint.model then
            return true
        end
    end

    return false
end

local device_init = function(self, device)
    for _, fingerprint in ipairs(ZIGBEE_POWER_METER_FINGERPRINTS) do
        -- KK: added additional condition
        if device:get_model() == fingerprint.model and fingerprint.battery then
            battery_defaults.build_linear_voltage_init(fingerprint.MIN_BAT, fingerprint.MAX_BAT)(self, device)
        end
    end
    for _, attribute in ipairs(ATTRIBUTES) do
        device:add_configured_attribute(attribute)
        -- KK removed: device:add_monitored_attribute(attribute)
    end
end

local do_refresh = function(self, device)
    device:refresh()
    -- KK: above device:refresh() already sends below commands
    -- KK: device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
    -- KK: device:send(SimpleMetering.attributes.InstantaneousDemand:read(device))
    if device:supports_capability(capabilities.battery) then
        device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
    end
end

local do_configure = function(self, device)
    device:refresh()
    device:configure()

    if device:supports_capability(capabilities.battery) then
        device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
    end
    for _, fingerprint in ipairs(ZIGBEE_POWER_METER_FINGERPRINTS) do
        -- KK: added additional condition
        if device:get_model() == fingerprint.model and fingerprint.preferences then
            local pulseConfiguration = tonumber(device.preferences.pulseConfiguration) or 1000
            -- KK: log.debug("Writing pulse configuration to: " .. pulseConfiguration)
            device:send(cluster_base.write_manufacturer_specific_attribute(device, SimpleMetering.ID, 0x0300, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, pulseConfiguration):to_endpoint(0x02))

            local currentSummation = tonumber(device.preferences.currentSummation) or 0
            -- KK: log.debug("Writing initial current summation to: " .. currentSummation)
            device:send(cluster_base.write_manufacturer_specific_attribute(device, SimpleMetering.ID, 0x0301, DEVELCO_MANUFACTURER_CODE, data_types.Uint48, currentSummation):to_endpoint(0x02))
        end
    end

    -- Divisor and multipler for PowerMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))

    device.thread:call_with_delay(5, function()
        do_refresh(self, device)
    end)
end

local function info_changed(driver, device, event, args)
    log.trace("Configuring sensor:"..event)
    for name, value in pairs(device.preferences) do
        if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
            if (name == "pulseConfiguration") then
                local pulseConfiguration = tonumber(device.preferences.pulseConfiguration)
                -- KK: log.debug("Configuring pulseConfiguration: "..pulseConfiguration)
                device:send(cluster_base.write_manufacturer_specific_attribute(device, SimpleMetering.ID, 0x0300, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, pulseConfiguration):to_endpoint(0x02))
            end
            if (name == "currentSummation") then
                local currentSummation = tonumber(device.preferences.currentSummation)
                -- KK: log.debug("Configuring currentSummation: "..currentSummation)
                device:send(cluster_base.write_manufacturer_specific_attribute(device, SimpleMetering.ID, 0x0301, DEVELCO_MANUFACTURER_CODE, data_types.Uint48, currentSummation):to_endpoint(0x02))
            end
        end
    end
    device.thread:call_with_delay(5, function()
        do_refresh(driver, device)
    end)
end

local function simple_metering_divisor_handler(driver, device, divisor, zb_rx)
    -- KK: I refactored it a bit
    local new_divisor = SIMPLE_METERING_DIVISOR
    local header = zb_rx.body and zb_rx.body.zcl_header
    if header and header.frame_ctrl:is_mfg_specific_set() then
        log.debug_with({ hub_logs = true }, string.format("Ignoring manufacturer-specific divisor report: %s", tostring(divisor.value)))
    elseif (divisor.value and divisor.value == 0) then
        log.warn_with({ hub_logs = true }, "Simple metering divisor reported as 0; forcing divisor to 1000")
    elseif (divisor.value and divisor.value > 0) then
        new_divisor = divisor.value
    end
    device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, raw_value, { persist = true })
end

local function instantaneous_demand_handler(driver, device, value, zb_rx)
    local raw_value = value.value
    --- demand = demand received * Multipler/Divisor
    local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
    local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or SIMPLE_METERING_DEFAULT_DIVISOR
    if raw_value < -8388607 or raw_value >= 8388607 then
        raw_value = 0
    end

    raw_value = raw_value * multiplier / divisor * 1000

    local raw_value_watts = raw_value
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.powerMeter.power({ value = raw_value_watts, unit = "W" }))
end

local function energy_meter_handler(driver, device, value, zb_rx)
    local raw_value = value.value
    log.trace("raw_value (1): "..raw_value)
    local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
    local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or SIMPLE_METERING_DEFAULT_DIVISOR

    if raw_value < 0 or raw_value >= 0xFFFFFFFFFFFF then
        log.warn_with({ hub_logs = true }, "Invalid CurrentSummationDelivered value received; ignoring report")
        return
    end

    log.trace("raw_value (before * multiplier/divisor): "..raw_value)
    log.trace("multiplier: "..multiplier)
    log.trace("divisor: "..divisor)
    raw_value = (raw_value * multiplier) / divisor
    log.trace("raw_value * multiplier / divisor is "..raw_value)

    local offset = device:get_field(zigbee_constants.ENERGY_METER_OFFSET) or 0
    log.trace("offset: "..offset)
    if raw_value < offset then
        --- somehow our value has gone below the offset, so we'll reset the offset, since the device seems to have
        offset = 0
        device:set_field(zigbee_constants.ENERGY_METER_OFFSET, offset, { persist = true })
        log.trace("offset 0 was set ")
    end
    raw_value = raw_value - offset
    log.trace("raw_value - offset "..raw_value)
    raw_value = raw_value * 1000 -- the unit of these values should be 'Wh'
    log.trace("raw_value = raw_value * 1000: "..raw_value)

    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))

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

local frient_power_meter_handler = {
    NAME = "frient power meter handler",
    lifecycle_handlers = {
        init = device_init,
        doConfigure = do_configure,
        infoChanged = info_changed
    },
    capability_handlers = {
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = do_refresh
        }
    },
    zigbee_handlers = {
        cluster = {
        },
        attr = {
            [SimpleMetering.ID] = {
                [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler,
                [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler,
                [SimpleMetering.attributes.Divisor.ID] = simple_metering_divisor_handler
            }
        }
    },
    sub_drivers = {
        require("frient/EMIZB-151")
    },
  can_handle = require("frient.can_handle"),
}

return frient_power_meter_handler