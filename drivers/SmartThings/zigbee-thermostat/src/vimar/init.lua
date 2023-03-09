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

local clusters        = require "st.zigbee.zcl.clusters"
local Thermostat      = clusters.Thermostat
local ThermostatControlSequence = Thermostat.attributes.ControlSequenceOfOperation

local capabilities              = require "st.capabilities"
local ThermostatMode            = capabilities.thermostatMode

local VIMAR_SUPPORTED_THERMOSTAT_MODES = {
  [ThermostatControlSequence.COOLING_ONLY]                    = { ThermostatMode.thermostatMode.off.NAME,
                                                                  ThermostatMode.thermostatMode.cool.NAME},
  [ThermostatControlSequence.HEATING_ONLY]                    = { ThermostatMode.thermostatMode.off.NAME,
                                                                  ThermostatMode.thermostatMode.heat.NAME}
}

local VIMAR_THERMOSTAT_FINGERPRINTS = {
  { mfr = "Vimar", model = "WheelThermostat_v1.0" }
}


local vimar_thermostat_can_handle = function(opts, driver, device)
  for _, fingerprint in ipairs(VIMAR_THERMOSTAT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
        return true
    end
  end
  return false
end

local vimar_thermostat_supported_modes_handler = function(driver, device, supported_modes)
  device:emit_event(ThermostatMode.supportedThermostatModes(VIMAR_SUPPORTED_THERMOSTAT_MODES[supported_modes.value], { visibility = { displayed = false } }))
end

local vimar_thermostat_do_refresh = function(self, device)
  -- Override device:refresh()
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.OccupiedCoolingSetpoint,
    Thermostat.attributes.ControlSequenceOfOperation,
    Thermostat.attributes.ThermostatRunningState,
    Thermostat.attributes.SystemMode,
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local vimar_thermostat_subdriver = {
  NAME = "Vimar Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = vimar_thermostat_supported_modes_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = vimar_thermostat_do_refresh,
    },
  },
  can_handle = vimar_thermostat_can_handle
}

return vimar_thermostat_subdriver
