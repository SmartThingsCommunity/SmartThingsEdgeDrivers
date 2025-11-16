-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"

local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement

local function active_power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) or 10

  raw_value = raw_value / divisor

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local function instantaneous_demand_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 10

  raw_value = raw_value / divisor

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local zigbee_switch_power = {
  NAME = "Zigbee Switch Power",
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = active_power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler
      }
    }
  },
  sub_drivers = require("zigbee-switch-power.sub_drivers"),
  can_handle = require("zigbee-switch-power.can_handle"),
}

return zigbee_switch_power
