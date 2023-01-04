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

local clusters = require "st.zigbee.zcl.clusters"
local Thermostat = clusters.Thermostat
local FanControl = clusters.FanControl
local capabilities = require "st.capabilities"

local ENDPOINT = 10

local function do_configure(driver, device)
  device:send_to_component("main", Thermostat.attributes.SystemMode:configure_reporting(device, 5, 1800, nil))
  device:send_to_component("main", Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(device, 5, 1800, 100))
  device:send_to_component("main", Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 5, 1800, 100))
  device:send_to_component("main", Thermostat.attributes.LocalTemperature:configure_reporting(device, 5, 1800, 100))
  device:send_to_component("main", FanControl.attributes.FanMode:configure_reporting(device, 5, 1800, nil))
end

local function do_refresh(driver, device, command)
  device:send_to_component("main", FanControl.attributes.FanMode:read(device))
  device:send_to_component("main", Thermostat.attributes.SystemMode:read(device))
  device:send_to_component("main", Thermostat.attributes.ControlSequenceOfOperation:read(device))
  device:send_to_component("main", Thermostat.attributes.OccupiedCoolingSetpoint:read(device))
  device:send_to_component("main", Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  device:send_to_component("main", Thermostat.attributes.LocalTemperature:read(device))
end

local function endpoint_to_component(device, ep)
  return "main"
end

local function component_to_endpoint(device, component_id)
  return ENDPOINT
end

local function initialize(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local function supported_thermostat_modes_handler(driver, device, value)
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes({
    capabilities.thermostatMode.thermostatMode.auto.NAME,
    capabilities.thermostatMode.thermostatMode.cool.NAME,
    capabilities.thermostatMode.thermostatMode.heat.NAME,
    capabilities.thermostatMode.thermostatMode.emergency_heat.NAME
  }, { visibility = { displayed = false } }))
end

local function supported_fan_modes_handler(driver, device, value)
  device:emit_event(capabilities.thermostatFanMode.supportedThermostatFanModes({
    capabilities.thermostatFanMode.thermostatFanMode.auto.NAME,
    capabilities.thermostatFanMode.thermostatFanMode.on.NAME,
    capabilities.thermostatFanMode.thermostatFanMode.circulate.NAME
  }, { visibility = { displayed = false } }))
end

local function added(driver, device)
  supported_thermostat_modes_handler(driver, device, nil)
  supported_fan_modes_handler(driver, device, nil)
  do_refresh(driver, device, nil)
end

-- The DTH only sends setpoint updates when the supported mode is appropriate for the setpoint.
local function heating_setpoint_handler(driver, device, value)
  local current_supported_mode = device:get_latest_state("main", capabilities.thermostatMode.ID, capabilities.thermostatMode.thermostatMode.NAME)
  if (current_supported_mode ~= capabilities.thermostatMode.thermostatMode.cool.NAME ) then
    device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = value.value/100.0, unit = "C"}))
  end
end

local function cooling_setpoint_handler(driver, device, value)
  local current_supported_mode = device:get_latest_state("main", capabilities.thermostatMode.ID, capabilities.thermostatMode.thermostatMode.NAME)
  if (current_supported_mode == capabilities.thermostatMode.thermostatMode.cool.NAME or current_supported_mode == capabilities.thermostatMode.thermostatMode.auto.NAME) then
    device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = value.value/100.0, unit = "C"}))
  end
end

local function set_cooling_setpoint(driver, device, command)
  device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = command.args.setpoint*1.0, unit = "C"}))
  device:send_to_component(command.component, Thermostat.attributes.OccupiedCoolingSetpoint:write(device, command.args.setpoint*100))
end

local function set_heating_setpoint(driver, device, command)
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = command.args.setpoint*1.0, unit = "C"}))
  device:send_to_component(command.component, Thermostat.attributes.OccupiedHeatingSetpoint:write(device, command.args.setpoint*100))
end

local leviton_thermostat = {
  NAME = "Leviton Thermostat Handler",
  lifecycle_handlers = {
    doConfigure = do_configure,
    init = initialize,
    added = added
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_cooling_setpoint
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    }
  },
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = heating_setpoint_handler,
        [Thermostat.attributes.OccupiedCoolingSetpoint.ID] = cooling_setpoint_handler,
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler,
      },
      [FanControl.ID] = {
        [FanControl.attributes.FanModeSequence.ID] = supported_fan_modes_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "HAI" and device:get_model() == "65A01-1"
  end
}

return leviton_thermostat
