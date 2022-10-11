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

local capabilities    = require "st.capabilities"
local ThermostatMode  = capabilities.thermostatMode


local LUX_KONOZ_THERMOSTAT_FINGERPRINTS = {
  { mfr = "LUX", model = "KONOZ" }
}

local is_lux_konoz = function(opts, driver, device)
  for _, fingerprint in ipairs(LUX_KONOZ_THERMOSTAT_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

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
  can_handle = is_lux_konoz
}

return lux_konoz
