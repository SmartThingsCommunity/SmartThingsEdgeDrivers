-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_constants = require "st.zigbee.constants"
local energy_meter_defaults = require "st.zigbee.defaults.energyMeter_defaults"
local configurations = require "configurations"

local SimpleMetering = clusters.SimpleMetering

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value

  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'

  energy_meter_defaults.energy_meter_handler(driver, device, value, zb_rx)
end

local do_configure = function(self, device)
  device:configure()
end

local device_init = function(self, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
end

local zigbee_metering_plug_power_conumption_report = {
  NAME = "zigbee metering plug power consumption report",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  },
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    doConfigure = do_configure
  },
  can_handle = require("zigbee-metering-plug-power-consumption-report.can_handle"),
}

return zigbee_metering_plug_power_conumption_report
