-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters        = require "st.zigbee.zcl.clusters"
local Thermostat      = clusters.Thermostat

local capabilities    = require "st.capabilities"
local ThermostatMode  = capabilities.thermostatMode




-- LUX KONOz reports extra ["auto", "emergency heat"] which, actually, aren't supported
local supported_thermostat_modes_handler = function(driver, device, supported_modes)
  device:emit_event(ThermostatMode.supportedThermostatModes({"off", "heat", "cool"}, { visibility = { displayed = false } }))
end

local lux_konoz = {
  NAME = "LUX KONOz Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler
      }
    }
  },
  can_handle = require("lux-konoz.can_handle"),
}

return lux_konoz
