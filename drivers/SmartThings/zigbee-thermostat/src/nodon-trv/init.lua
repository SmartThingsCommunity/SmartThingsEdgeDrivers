-- Copyright 2024 SmartThings
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
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local log = require "log"

local Thermostat = clusters.Thermostat
local PowerConfiguration = clusters.PowerConfiguration

local NODON_TRV_FINGERPRINTS = {
  { mfr = "NodOn", model = "TRV-4-1-00" }
}

local MIN_SETPOINT = 8.0
local MAX_SETPOINT = 28.0

local is_nodon_trv_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(NODON_TRV_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

-- Handle setHeatingSetpoint command with range validation
local function set_heating_setpoint_handler(driver, device, command)
  local setpoint_celsius = command.args.setpoint

  -- Enforce device min/max limits (8-28°C for NodOn TRV)
  if setpoint_celsius < MIN_SETPOINT then
    log.warn(string.format("Setpoint %.1f°C below minimum, clamping to %.1f°C", setpoint_celsius, MIN_SETPOINT))
    setpoint_celsius = MIN_SETPOINT
  elseif setpoint_celsius > MAX_SETPOINT then
    log.warn(string.format("Setpoint %.1f°C above maximum, clamping to %.1f°C", setpoint_celsius, MAX_SETPOINT))
    setpoint_celsius = MAX_SETPOINT
  end

  local setpoint_zigbee = math.floor(setpoint_celsius * 100)  -- Convert to 0.01°C units
  log.info(string.format("Setting heating setpoint: %.1f°C (Zigbee: %d)", setpoint_celsius, setpoint_zigbee))

  -- Write to thermostat cluster
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, setpoint_zigbee))

  -- Read back to confirm
  device.thread:call_with_delay(1, function(d)
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  end)
end

-- Configure battery-optimized reporting for NodOn TRV
local function do_configure(driver, device)
  device:configure()

  -- Bind clusters
  device:send(device_management.build_bind_request(device, Thermostat.ID, driver.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui))

  -- Configure battery-optimized reporting
  -- Temperature: report every 5s-1h, when it changes by 0.5°C (50 = 0.50°C in 0.01°C units)
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 5, 3600, 50))

  -- Setpoint: report every 1s-24h, when it changes by 0.5°C
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 1, 86400, 50))

  -- Mode: report every 1s-24h, when it changes
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 1, 86400, 1))

  -- Battery: report every 5min-24h, when it changes by 1% (2 = 1% in 0-200 scale)
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 300, 86400, 2))

  -- Read device capabilities
  device:send(Thermostat.attributes.ControlSequenceOfOperation:read(device))
  device:send(Thermostat.attributes.MinHeatSetpointLimit:read(device))
  device:send(Thermostat.attributes.MaxHeatSetpointLimit:read(device))
end

local nodon_trv_thermostat = {
  NAME = "NodOn Thermostatic Radiator Valve Handler",
  capability_handlers = {
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_defaults.battery_percentage_handler
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = is_nodon_trv_thermostat
}

return nodon_trv_thermostat
