-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local RelativeHumidity = clusters.RelativeHumidity
local Thermostat = clusters.Thermostat
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration

local do_refresh = function(self, device)
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.PIHeatingDemand,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode,
    ThermostatUserInterfaceConfiguration.attributes.KeypadLockout,
    RelativeHumidity.attributes.MeasuredValue
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local device_added = function(self, device)
  device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
  do_refresh(self, device)
end

local function do_configure(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 10, 60, 50))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 1, 600, 50))
  device:send(Thermostat.attributes.PIHeatingDemand:configure_reporting(device, 1, 3600, 1))

  device:send(ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:configure_reporting(device, 1, 0, 1))
  device:send(ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:configure_reporting(device, 1, 0, 1))
  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(device, 10, 300, 1))
end

local stelpro_maestro_othermostat = {
  NAME = "Stelpro Maestro Thermostat Handler",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = require("stelpro.stelpro_maestrostat.can_handle")
}

return stelpro_maestro_othermostat
