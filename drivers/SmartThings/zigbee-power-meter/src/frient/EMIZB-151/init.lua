-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zigbee_constants = require "st.zigbee.constants"
local capabilities = require "st.capabilities"

local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local utils = require "frient.utils"

local data_types = require "st.zigbee.data_types"
local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local SIMPLE_METERING_DEFAULT_DIVISOR = 1000

local AC_VOLTAGE_MULTIPLIER_KEY = "_electrical_measurement_ac_voltage_multiplier"
local AC_CURRENT_MULTIPLIER_KEY = "_electrical_measurement_ac_current_multiplier"
local AC_VOLTAGE_DIVISOR_KEY = "_electrical_measurement_ac_voltage_divisor"
local AC_CURRENT_DIVISOR_KEY = "_electrical_measurement_ac_current_divisor"

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
    attribute = SimpleMetering.attributes.InstantaneousDemand.ID,
    minimum_interval = 5,
    maximum_interval = 3600,
    data_type = data_types.Int24,
    reportable_change = 1
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
  end

  if device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) == nil then
    device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, SIMPLE_METERING_DEFAULT_DIVISOR, { persist = true })
  end
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Divisor and multipler for PowerMeter
  device:send(SimpleMetering.attributes.Divisor:read(device))
  device:send(SimpleMetering.attributes.Multiplier:read(device))
end

local instantaneous_demand_handler = function(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or SIMPLE_METERING_DEFAULT_DIVISOR

  raw_value = raw_value * multiplier / divisor * 1000

  -- The result is already in watts, no need to multiply by 1000
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local current_summation_delivered_handler = function(driver, device, value, zb_rx)
  local raw_value = value.value

  -- Handle potential overflow values
  if raw_value < 0 or raw_value >= 0xFFFFFFFFFFFF then
    return
  end

  local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or SIMPLE_METERING_DEFAULT_DIVISOR

  raw_value = raw_value * multiplier / divisor * 1000
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))

  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end

  local current_time = os.time()
  local last_report_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_report_time = last_report_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
  if current_time < next_report_time then
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
    return
  end

  local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or 1000

  raw_value = raw_value * multiplier / divisor * 1000
  device:emit_component_event(device.profile.components['production'], capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))
end

local electrical_measurement_ac_voltage_multiplier_handler = function(driver, device, multiplier, zb_rx)
  local raw_value = multiplier.value
  device:set_field(AC_VOLTAGE_MULTIPLIER_KEY, raw_value, { persist = true })
end

local electrical_measurement_ac_voltage_divisor_handler = function(driver, device, divisor, zb_rx)
  local raw_value = divisor.value
  if raw_value == 0 then
    return
  end
  device:set_field(AC_VOLTAGE_DIVISOR_KEY, raw_value, { persist = true })
end

local electrical_measurement_ac_current_multiplier_handler = function(driver, device, multiplier, zb_rx)
  local raw_value = multiplier.value
  device:set_field(AC_CURRENT_MULTIPLIER_KEY, raw_value, { persist = true })
end

local electrical_measurement_ac_current_divisor_handler = function(driver, device, divisor, zb_rx)
  local raw_value = divisor.value
  if raw_value == 0 then
    return
  end
  device:set_field(AC_CURRENT_DIVISOR_KEY, raw_value, { persist = true })
end

local measurement_handler = function(component, multiplier_key, divisor_key, emit_fn, unit)
  local handler = function(driver, device, value, zb_rx)
    local raw_value = value.value
    -- By default emit raw value
    local multiplier = device:get_field(multiplier_key) or 1
    local divisor = device:get_field(divisor_key) or 1

    raw_value = raw_value * multiplier / divisor

    device:emit_component_event(device.profile.components[component], emit_fn({ value = raw_value, unit = unit }))
  end

  return handler
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
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ACVoltageDivisor.ID] = electrical_measurement_ac_voltage_divisor_handler,
        [ElectricalMeasurement.attributes.ACVoltageMultiplier.ID] = electrical_measurement_ac_voltage_multiplier_handler,
        [ElectricalMeasurement.attributes.ACCurrentDivisor.ID] = electrical_measurement_ac_current_divisor_handler,
        [ElectricalMeasurement.attributes.ACCurrentMultiplier.ID] = electrical_measurement_ac_current_multiplier_handler,
        [ElectricalMeasurement.attributes.ActivePower.ID] = measurement_handler("phaseA", zigbee_constants.ELECTRICAL_MEASUREMENT_MULTIPLIER_KEY, zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, capabilities.powerMeter.power, "W"),
        [ElectricalMeasurement.attributes.RMSVoltage.ID] = measurement_handler("phaseA", AC_VOLTAGE_MULTIPLIER_KEY, AC_VOLTAGE_DIVISOR_KEY, capabilities.voltageMeasurement.voltage, "V"),
        [ElectricalMeasurement.attributes.RMSCurrent.ID] = measurement_handler("phaseA", AC_CURRENT_MULTIPLIER_KEY, AC_CURRENT_DIVISOR_KEY, capabilities.currentMeasurement.current, "A"),
        [ElectricalMeasurement.attributes.ActivePowerPhB.ID] = measurement_handler("phaseB", zigbee_constants.ELECTRICAL_MEASUREMENT_MULTIPLIER_KEY, zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, capabilities.powerMeter.power, "W"),
        [ElectricalMeasurement.attributes.RMSVoltagePhB.ID] = measurement_handler("phaseB", AC_VOLTAGE_MULTIPLIER_KEY, AC_VOLTAGE_DIVISOR_KEY, capabilities.voltageMeasurement.voltage, "V"),
        [ElectricalMeasurement.attributes.RMSCurrentPhB.ID] = measurement_handler("phaseB", AC_CURRENT_MULTIPLIER_KEY, AC_CURRENT_DIVISOR_KEY, capabilities.currentMeasurement.current, "A"),
        [ElectricalMeasurement.attributes.ActivePowerPhC.ID] = measurement_handler("phaseC", zigbee_constants.ELECTRICAL_MEASUREMENT_MULTIPLIER_KEY, zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, capabilities.powerMeter.power, "W"),
        [ElectricalMeasurement.attributes.RMSVoltagePhC.ID] = measurement_handler("phaseC", AC_VOLTAGE_MULTIPLIER_KEY, AC_VOLTAGE_DIVISOR_KEY, capabilities.voltageMeasurement.voltage, "V"),
        [ElectricalMeasurement.attributes.RMSCurrentPhC.ID] = measurement_handler("phaseC", AC_CURRENT_MULTIPLIER_KEY, AC_CURRENT_DIVISOR_KEY, capabilities.currentMeasurement.current, "A")
      }
    }
  },
  can_handle = require("frient.EMIZB-151.can_handle")
}

return frient_emi