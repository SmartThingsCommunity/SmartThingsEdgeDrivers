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
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })

local THERMOSTAT_MIN_HEATING_SETPOINT = 5.0
local THERMOSTAT_MAX_HEATING_SETPOINT = 30.0

local STELPRO_KI_THERMOSTAT_FINGERPRINTS = {
  { manufacturerId = 0x0239, productType = 0x0001, productId = 0x0001 } -- Stelpro Ki Thermostat
}

local function can_handle_stelpro_ki_thermostat(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(STELPRO_KI_THERMOSTAT_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end

  return false
end

local function set_heating_setpoint(driver, device, command)
  local value = command.args.setpoint
  if (value >= 40) then -- assume this is a fahrenheit value
    value = utils.f_to_c(value)
  end
  if THERMOSTAT_MIN_HEATING_SETPOINT <= value and THERMOSTAT_MAX_HEATING_SETPOINT >= value then
    local scale = device:get_field(constants.TEMPERATURE_SCALE)
    if (scale == ThermostatSetpoint.scale.FAHRENHEIT) then
      value = utils.c_to_f(value) -- the device has reported using F, so set using F
    end

    local set = ThermostatSetpoint:Set({
      setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
      scale = scale,
      value = value
    })
    device:send_to_component(set, command.component)

    local follow_up_poll = function()
      device:send_to_component(
        ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}),
        command.component
      )
    end

    device.thread:call_with_delay(1, follow_up_poll)
  end
end

local function sensor_multilevel_report_handler(self, device, cmd)
  if (cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE) then
    if cmd.args.scale ~= SensorMultilevel.scale.temperature.CELSIUS and cmd.args.scale ~= SensorMultilevel.scale.temperature.FAHRENHEIT then
      if cmd.args.sensor_value == 0x7ffd then
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.freeze())
      elseif cmd.args.sensor_value == 0x7fff then
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.heat())
      end
    else
      local scale = 'C'
      local current_temperature_alarm = device:get_latest_state("main", capabilities.temperatureAlarm.ID, capabilities.temperatureAlarm.temperatureAlarm.NAME)

      if (cmd.args.scale == SensorMultilevel.scale.temperature.FAHRENHEIT) then scale = 'F' end

      if cmd.args.sensor_value <= (scale == 'C' and 0 or 32) then
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.freeze())
      elseif cmd.args.sensor_value >= (scale == 'C' and 50 or 122) then
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.heat())
      elseif current_temperature_alarm ~= "cleared" then
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
      end

      device:emit_event(capabilities.temperatureMeasurement.temperature({value = cmd.args.sensor_value, unit = scale}))
    end
  end
end

local function device_added(self, device)
  device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
end

local stelpro_ki_thermostat = {
  NAME = "stelpro ki thermostat",
  zwave_handlers = {
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    }
  },
  capability_handlers = {
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_stelpro_ki_thermostat,
}

return stelpro_ki_thermostat
