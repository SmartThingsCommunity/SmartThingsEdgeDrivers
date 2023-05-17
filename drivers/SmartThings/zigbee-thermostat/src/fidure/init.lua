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

local device_management = require "st.zigbee.device_management"

local clusters                      = require "st.zigbee.zcl.clusters"
local Thermostat                    = clusters.Thermostat

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 20, 300, 20)) -- report temperature changes over 0.2°C
  device:send(Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(device, 10, 320, 50))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 10, 320, 50))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 10, 305))
  device:send(Thermostat.attributes.ThermostatRunningState:configure_reporting(device, 10, 325))
end

local fidure_thermostat = {
  NAME = "Fidure Thermostat Handler",
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.ThermostatRunningMode.ID] = function() end
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Fidure" and device:get_model() == "A1732R3"
  end
}

return fidure_thermostat
