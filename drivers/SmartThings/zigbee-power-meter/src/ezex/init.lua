-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local energy_meter_defaults = require "st.zigbee.defaults.energyMeter_defaults"
local configurations = require "configurations"



local instantaneous_demand_configuration = {
  cluster = SimpleMetering.ID,
  attribute = SimpleMetering.attributes.InstantaneousDemand.ID,
  minimum_interval = 5,
  maximum_interval = 3600,
  data_type = SimpleMetering.attributes.InstantaneousDemand.base_type,
  reportable_change = 500
}

local do_configure = function(self, device)
  device:refresh()
  device:configure()
end

local device_init = function(self, device)
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000000, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, {persist = true})
  device:remove_configured_attribute(ElectricalMeasurement.ID, ElectricalMeasurement.attributes.ActivePower.ID)
  device:remove_configured_attribute(ElectricalMeasurement.ID, ElectricalMeasurement.attributes.ACPowerDivisor.ID)
  device:remove_configured_attribute(ElectricalMeasurement.ID, ElectricalMeasurement.attributes.ACPowerMultiplier.ID)
  device:add_configured_attribute(instantaneous_demand_configuration)
end

local function noop_active_power(driver, device, value, zb_rx) end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value_miliwatts = value.value
  local raw_value_watts = raw_value_miliwatts / 1000
  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value_watts - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({energy = raw_value_watts, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'

  energy_meter_defaults.energy_meter_handler(driver, device, value, zb_rx)
end

local ezex_power_meter_handler = {
  NAME = "ezex power meter handler",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = noop_active_power
      }
    }
  },
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    doConfigure = do_configure,
  },
  can_handle = require("ezex.can_handle"),
}

return ezex_power_meter_handler
