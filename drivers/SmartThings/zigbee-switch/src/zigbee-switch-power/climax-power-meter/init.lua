-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local power_meter_defaults = require "st.zigbee.defaults.powerMeter_defaults"

local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering

local climax_power_meter = {
  NAME = "Climax Power Meter",
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_defaults.active_power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = power_meter_defaults.instantaneous_demand_handler
      }
    }
  },
  can_handle = require("zigbee-switch-power.climax-power-meter.can_handle")
}

return climax_power_meter
