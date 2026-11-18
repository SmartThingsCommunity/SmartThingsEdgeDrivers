-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local SimpleMetering = clusters.SimpleMetering

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
  can_handle = require("zigbee-dimmer-power-energy.can_handle"),
}

return zigbee_dimmer_power_energy_handler
