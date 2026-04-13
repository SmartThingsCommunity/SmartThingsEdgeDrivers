-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zigbee_constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local configurations = require "configurations"

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
    -- Divisor and multipler for EnergyMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))
  end
end

local device_init = function(self, device)
  -- We check the keys to see if they're already set so that we don't clobber the values w/ the defaults if they already exist.
  if device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) == nil then
    device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
  end

  if device:get_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) == nil then
    device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1000, {persist = true})
  end
end

local zigbee_power_meter_driver_template = {
  supported_capabilities = {
    capabilities.refresh,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.powerConsumptionReport,
    capabilities.battery,
  },
  zigbee_handlers = {
    global = {
      [SimpleMetering.ID] = {
        [zcl_global_commands.CONFIGURE_REPORTING_RESPONSE_ID] = configurations.handle_reporting_config_response
      },
     [ElectricalMeasurement.ID] = {
        [zcl_global_commands.CONFIGURE_REPORTING_RESPONSE_ID] = configurations.handle_reporting_config_response
      }
    }
  },
  current_config_version = 1,
  sub_drivers = require("sub_drivers"),
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    doConfigure = do_configure,
  },
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_power_meter_driver_template, zigbee_power_meter_driver_template.supported_capabilities)
local zigbee_power_meter = ZigbeeDriver("zigbee_power_meter", zigbee_power_meter_driver_template)
zigbee_power_meter:run()
