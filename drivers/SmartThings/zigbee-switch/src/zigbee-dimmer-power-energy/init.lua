-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local SimpleMetering = clusters.SimpleMetering
local constants = require "st.zigbee.constants"
local configurations = require "configurations"

local device_init = function(self, device)
  local customEnergyDivisor = 10000
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, customEnergyDivisor, {persist = true})
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if  device:supports_capability(capabilities.powerMeter) then
    -- Divisor and multipler for PowerMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))
  end
end

local instantaneous_demand_handler = function(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = 10
  raw_value = raw_value / divisor
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.powerMeter.power({value = raw_value, unit = "W" }))
end

local zigbee_dimmer_power_energy_handler = {
  NAME = "zigbee dimmer power energy handler",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler
      }
    }
  },
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    doConfigure = do_configure,
  },
  can_handle = require("zigbee-dimmer-power-energy.can_handle"),
}

return zigbee_dimmer_power_energy_handler
