-- Copyright 2023 SmartThings
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

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local log = require "log"
local utils = require "st.utils"

-- local fanControl = capabilities["insideimage13541.fanControl3"]
-- local fanControlId = "insideimage13541.fanControl3"

-- local THERMOSTAT_MODE_MAP = {
--   [clusters.Thermostat.types.ThermostatSystemMode.OFF]               = capabilities.thermostatMode.thermostatMode.off,
--   [clusters.Thermostat.types.ThermostatSystemMode.AUTO]              = capabilities.thermostatMode.thermostatMode.auto,
--   [clusters.Thermostat.types.ThermostatSystemMode.COOL]              = capabilities.thermostatMode.thermostatMode.cool,
--   [clusters.Thermostat.types.ThermostatSystemMode.HEAT]              = capabilities.thermostatMode.thermostatMode.heat,
--   [clusters.Thermostat.types.ThermostatSystemMode.EMERGENCY_HEATING] = capabilities.thermostatMode.thermostatMode.emergency_heat,
--   [clusters.Thermostat.types.ThermostatSystemMode.FAN_ONLY]          = capabilities.thermostatMode.thermostatMode.fanOnly
-- }

-- local THERMOSTAT_OPERATING_MODE_MAP = {
--   [0]		= capabilities.thermostatOperatingState.thermostatOperatingState.heating,
--   [1]		= capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
--   [2]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
-- }

local function device_init(driver, device)
  device:subscribe()
end

local function device_added(driver, device)
  -- device:send(clusters.Thermostat.attributes.ControlSequenceOfOperation:read(device))
  -- device:send(clusters.FanControl.attributes.FanModeSequence:read(device))
end

-- Capability Handlers --
-- local function handle_switch_on(driver, device, cmd)
--   local endpoint_id = device:component_to_endpoint(cmd.component)
--   local req = clusters.OnOff.server.commands.On(device, endpoint_id)
--   device:send(req)
-- end

-- local function handle_switch_off(driver, device, cmd)
--   local endpoint_id = device:component_to_endpoint(cmd.component)
--   local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
--   device:send(req)
-- end

-- local function set_thermostat_mode(driver, device, cmd)
--   local mode_id = nil
--   for value, mode in pairs(THERMOSTAT_MODE_MAP) do
--     if mode.NAME == cmd.args.mode then
--       mode_id = value
--       break
--     end
--   end
--   if mode_id then
--     device:send(clusters.Thermostat.attributes.SystemMode:write(device, device:component_to_endpoint(cmd.component), mode_id))
--   end
-- end

-- local thermostat_mode_setter = function(mode_name)
--   return function(driver, device, cmd)
--     return set_thermostat_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
--   end
-- end

-- local function set_fan_mode(driver, device, cmd)
--   local fan_mode_id = nil
--   if cmd.args.mode == fanControl.fanMode.off.NAME then
--     fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
--   elseif cmd.args.mode == fanControl.fanMode.low.NAME then
--     fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
--   elseif cmd.args.mode == fanControl.fanMode.medium.NAME then
--     fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
--   elseif cmd.args.mode == fanControl.fanMode.high.NAME then
--     fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
--   elseif cmd.args.mode == fanControl.fanMode.auto.NAME then
--     fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
--   else
--     fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
--   end
--   if fan_mode_id then
--     device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
--   end
-- end

-- local function set_setpoint(setpoint)
--   return function(driver, device, cmd)
--     local value = cmd.args.setpoint
--     if (value >= 40) then -- assume this is a fahrenheit value
--       value = f_to_c(value)
--     end

--     device:send(setpoint:write(device, device:component_to_endpoint(cmd.component), utils.round(value * 100.0)))
--   end
-- end

-- Matter Handlers --
local function temp_event_handler(attribute)
  return function(driver, device, ib, response)
    local temp = ib.data.value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = temp, unit = unit}))
  end
end

local function humidity_attr_handler(driver, device, ib, response)
  local humidity = math.floor(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local function smoke_state_event_handler(driver, device, ib, response)
  local humidity = 10
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.SmokeState.ID] = smoke_state_event_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      }
    }
  },
  subscribed_attributes = {
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.SmokeState
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    }
  },
  capability_handlers = {
    -- [capabilities.switch.ID] = {
    --   [capabilities.switch.commands.on.NAME] = handle_switch_on,
    --   [capabilities.switch.commands.off.NAME] = handle_switch_off,
    -- },
    -- [capabilities.thermostatMode.ID] = {
    --   [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
    --   [capabilities.thermostatMode.commands.auto.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.auto.NAME),
    --   [capabilities.thermostatMode.commands.off.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.off.NAME),
    --   [capabilities.thermostatMode.commands.cool.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.cool.NAME),
    --   [capabilities.thermostatMode.commands.heat.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.heat.NAME),
    --   [capabilities.thermostatMode.commands.emergencyHeat.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.emergency_heat.NAME)
    -- },
    -- [capabilities.thermostatCoolingSetpoint.ID] = {
    --   [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedCoolingSetpoint)
    -- },
    -- [capabilities.thermostatHeatingSetpoint.ID] = {
    --   [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedHeatingSetpoint)
    -- },
    -- [fanControlId] = {
    --   [fanControl.commands.setFanMode.NAME] = set_fan_mode,
    -- }
  },
}

local matter_driver = MatterDriver("matter-smoke-co-alarm", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
