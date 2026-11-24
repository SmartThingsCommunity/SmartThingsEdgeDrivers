-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local constants = require "st.zigbee.constants"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local SimpleMetering = zcl_clusters.SimpleMetering

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(constants.ELECTRICAL_MEASUREMENT_MULTIPLIER_KEY) or 1
  local divisor = 10

  raw_value = raw_value * multiplier / divisor
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local robb_dimmer_handler = {
  NAME = "ROBB smarrt dimmer",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = power_meter_handler
      }
    }
  },
  can_handle = require("robb.can_handle"),
}

return robb_dimmer_handler
