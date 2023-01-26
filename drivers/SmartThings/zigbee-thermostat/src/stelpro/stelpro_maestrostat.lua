-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local RelativeHumidity = clusters.RelativeHumidity
local Thermostat = clusters.Thermostat
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration

local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState

local STELPRO_THERMOSTAT_FINGERPRINTS = {
  { mfr = "Stelpro", model = "MaestroStat" },
}

local is_stelpro_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(STELPRO_THERMOSTAT_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

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
  -- device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
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
  can_handle = is_stelpro_thermostat
}

return stelpro_maestro_othermostat
