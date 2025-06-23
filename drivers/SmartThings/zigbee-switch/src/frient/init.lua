-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"
local log = require "log"
local util = require "st.utils"
local configurationMap = require("configurations")

local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local Alarms = clusters.Alarms

local VOLTAGE_MEASUREMENT_MULTIPLIER_KEY = "_voltage_measurement_multiplier"
local VOLTAGE_MEASUREMENT_DIVISOR_KEY    = "_voltage_measurement_divisor"
local CURRENT_MEASUREMENT_MULTIPLIER_KEY = "_current_measurement_multiplier"
local CURRENT_MEASUREMENT_DIVISOR_KEY    = "_current_measurement_divisor"

local FRIENT_SMART_PLUG_FINGERPRINTS = {
    { mfr = "frient A/S", model = "SPLZB-131" },
    { mfr = "frient A/S", model = "SPLZB-132" },
    { mfr = "frient A/S", model = "SPLZB-134" },
    { mfr = "frient A/S", model = "SPLZB-137" },
    { mfr = "frient A/S", model = "SPLZB-141" },
    { mfr = "frient A/S", model = "SPLZB-142" },
    { mfr = "frient A/S", model = "SPLZB-144" },
    { mfr = "frient A/S", model = "SPLZB-147" },
    { mfr = "frient A/S", model = "SMRZB-143" },
    { mfr = "frient A/S", model = "SMRZB-153" },
    { mfr = "frient A/S", model = "SMRZB-332" },
    { mfr = "frient A/S", model = "SMRZB-342" },
}

local POWER_FAILURE_ALARM_CODE = 0x03


local function alarm_report_handler(driver, device, zb_rx)
    local alarm_status = zb_rx.body.zcl_body
    log.error("Received alarm report:"..util.stringify_table(zb_rx.body.zcl_body, nil, true))
    if ((alarm_status.cluster_identifier.value == SimpleMetering.ID) and (alarm_status.alarm_code.value == POWER_FAILURE_ALARM_CODE)) then
        device.thread:call_with_delay(2, function(d)
            device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.powerSource.powerSource.unknown())
        end
        )
    end
end

local function device_added(driver, device)
end

-- Handler for voltage measurement
local function voltage_measurement_handler(driver, device, value, zb_rx)
    local raw_value  = value.value
    -- By default emit raw value
    local multiplier = device:get_field(VOLTAGE_MEASUREMENT_MULTIPLIER_KEY) or 1
    local divisor    = device:get_field(VOLTAGE_MEASUREMENT_DIVISOR_KEY) or 1

    if divisor == 0 then
        log.warn("Voltage scale divisor is 0; using 1 to avoid division by zero")
        divisor = 1
    end

    raw_value  = raw_value * multiplier / divisor

    local mult = 10 ^ 1 -- Round off to 1 decimal place
    raw_value  = math.floor(raw_value * mult + 0.5) / mult

    if device:supports_capability(capabilities.voltageMeasurement) then
        device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.voltageMeasurement.voltage({ value = raw_value, unit = "V" }))
    end
    if device:supports_capability(capabilities.powerSource) then
        device:emit_event(capabilities.powerSource.powerSource.mains())
    end
end

local function current_measurement_divisor_handler(driver, device, divisor, zb_rx)
    log.info("current divisor value = ", divisor.value)
    local raw_value = divisor.value
    device:set_field(CURRENT_MEASUREMENT_DIVISOR_KEY, raw_value, { persist = true })
end

local function current_measurement_multiplier_handler(driver, device, multiplier, zb_rx)
    log.info("current multipl value = ", multiplier.value)
    local raw_value = multiplier.value
    device:set_field(CURRENT_MEASUREMENT_MULTIPLIER_KEY, raw_value, { persist = true })
end

local function voltage_measurement_divisor_handler(driver, device, divisor, zb_rx)
    log.info("V divisor value = ", divisor.value)

    local raw_value = divisor.value
    device:set_field(VOLTAGE_MEASUREMENT_DIVISOR_KEY, raw_value, { persist = true })
end

local function voltage_measurement_multiplier_handler(driver, device, multiplier, zb_rx)
    log.info("Volt Multiplayer value = ")
    local raw_value = multiplier.value

    device:set_field(VOLTAGE_MEASUREMENT_MULTIPLIER_KEY, raw_value, { persist = true })
end

-- Handler for current measurement
local function current_measurement_handler(driver, device, value, zb_rx)
    local raw_value  = value.value
    -- By default emit raw value
    local multiplier = device:get_field(CURRENT_MEASUREMENT_MULTIPLIER_KEY) or 1
    local divisor    = device:get_field(CURRENT_MEASUREMENT_DIVISOR_KEY) or 1

    if divisor == 0 then
        log.warn("Current scale divisor is 0; using 1 to avoid division by zero")
        divisor = 1
    end

    raw_value  = raw_value * multiplier / divisor

    local mult = 10 ^ 2 -- Round off to 2 decimal places
    raw_value  = math.floor(raw_value * mult + 0.5) / mult

    if device:supports_capability(capabilities.currentMeasurement) then
        device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.currentMeasurement.current({ value = raw_value, unit = "A" }))
    end
end

-- Device init function
local function device_init(driver, device)
    device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
    device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1000, {persist = true})
    -- Indicate device is powered by mains
    if device:supports_capability(capabilities.powerSource) then
        device:emit_event(capabilities.powerSource.powerSource.mains())
    end
end

local function do_configure(driver, device)
    local configuration = configurationMap.get_device_configuration(device)
    if configuration ~= nil then
        for _, attribute in ipairs(configuration) do
            device:add_configured_attribute(attribute)
            device:add_monitored_attribute(attribute)
        end
    end
    device:configure()

    local alarms_endpoint = device:get_endpoint(Alarms.ID) or device.fingerprinted_endpoint_id
    -- Make sure we have a valid endpoint number before sending the bind request
    if alarms_endpoint ~= nil then
        log.debug(string.format("Binding to Alarms cluster on endpoint %d", alarms_endpoint))
        device:send(ElectricalMeasurement.attributes.ACVoltageMultiplier:read(device))
        device:send(ElectricalMeasurement.attributes.ACVoltageDivisor:read(device))
        device:send(ElectricalMeasurement.attributes.ACCurrentMultiplier:read(device))
        device:send(ElectricalMeasurement.attributes.ACCurrentDivisor:read(device))
    else
        log.warn("No valid endpoint found for Alarms cluster binding")
    end
    device:refresh()
end

-- Function to determine if the driver can handle this device
local function can_handle_frient_smart_plug(opts, driver, device, ...)
    for _, fingerprint in ipairs(FRIENT_SMART_PLUG_FINGERPRINTS) do
        if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
            local subdriver = require("frient")
            return true, subdriver
        end
    end
    return false
end

-- Main driver definition
local frient_smart_plug = {
    NAME = "frient Smart Plug",
    zigbee_handlers = {
        cluster = {
            [Alarms.ID] = {
                [Alarms.client.commands.Alarm.ID] = alarm_report_handler
            }
        },
        attr = {
            [ElectricalMeasurement.ID] = {
                [ElectricalMeasurement.attributes.ACVoltageMultiplier.ID] = voltage_measurement_multiplier_handler,
                [ElectricalMeasurement.attributes.ACVoltageDivisor.ID] = voltage_measurement_divisor_handler,
                [ElectricalMeasurement.attributes.RMSVoltage.ID] = voltage_measurement_handler,
                [ElectricalMeasurement.attributes.ACCurrentMultiplier.ID] = current_measurement_multiplier_handler,
                [ElectricalMeasurement.attributes.ACCurrentDivisor.ID] = current_measurement_divisor_handler,
                [ElectricalMeasurement.attributes.RMSCurrent.ID] = current_measurement_handler
            }
        },
    },
    lifecycle_handlers = {
        init = device_init,
        doConfigure = do_configure,
        added = device_added,
    },
    can_handle = can_handle_frient_smart_plug
}

return frient_smart_plug