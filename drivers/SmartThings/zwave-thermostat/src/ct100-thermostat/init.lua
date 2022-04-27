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
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
--- @type st.zwave.CommandClass.ThermostatFanMode
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({ version = 3 })
--- @type st.zwave.CommandClass.ThermostatFanState
local ThermostatFanState = (require "st.zwave.CommandClass.ThermostatFanState")({ version = 2 })
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
--- @type st.zwave.CommandClass.ThermostatOperatingState
local ThermostatOperatingState = (require "st.zwave.CommandClass.ThermostatOperatingState")({ version = 1 })
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })

local CT100_THERMOSTAT_FINGERPRINTS = {
  { manufacturerId = 0x0098, productType = 0x6401, productId = 0x0107 }, -- 2Gig CT100 Programmable Thermostat
  { manufacturerId = 0x0098, productType = 0x6501, productId = 0x000C }, -- Iris Thermostat
}

-- Constants
local TEMPERATURE_SCALE = "temperature_scale"
local PRECISION = "precision"
local CURRENT_HEATING_SETPOINT = "current_heating_setpoint"
local CURRENT_COOLING_SETPOINT = "currnet_cooling_setpoint"
local MODE = "mode"
local TEMPERATURE = "temperature"
local HEATING_SETPOINT_IS_LIMITED = "heating_setpoint_is_limited"
local COOLING_SETPOINT_IS_LIMITED = "cooling_setpoint_is_limited"

local MIN_HEATING_SETPOINT = 35.0
local MAX_HEATING_SETPOINT = 92.0
local MIN_COOLING_SETPOINT = 38.0
local MAX_COOLING_SETPOINT = 95.0

local function can_handle_ct100_thermostat(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(CT100_THERMOSTAT_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end

  return false
end

local function send_setpoint_to_device(device, data)
  local scale = device:get_field(TEMPERATURE_SCALE)
  local precision = device:get_field(PRECISION)

  if data.target_heating_setpoint ~= nil then
    device:set_field(HEATING_SETPOINT_IS_LIMITED, true, {persist = true})
    device:send(ThermostatSetpoint:Set({
      setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
      scale = scale,
      precision = precision,
      value = data.target_heating_setpoint
    }))
  end

  if data.target_cooling_setpoint ~= nil then
    device:set_field(COOLING_SETPOINT_IS_LIMITED, true, {persist = true})
    device:send(ThermostatSetpoint:Set({
      setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
      scale = scale,
      precision = precision,
      value = data.target_cooling_setpoint
    }))
  end

  device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}))
  device:send(ThermostatOperatingState:Get({}))

  if data.target_heating_setpoint ~= nil then
    device:send(ThermostatSetpoint:Get({
      setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
    }))
  end

  if data.target_cooling_setpoint ~= nil then
    device:send(ThermostatSetpoint:Get({
      setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
    }))
  end
end

local function f_to_c(fahrenheit)
  return (utils.round((fahrenheit - 32 * 5 / 9.0) * 2) / 2)
end

local function enforce_setpoint_limits(device, setpoint_type, data)
  local device_scale = device:get_field(TEMPERATURE_SCALE)
  local min_heating_setpoint = device_scale == ThermostatSetpoint.scale.CELSIUS and f_to_c(MIN_HEATING_SETPOINT) or MIN_HEATING_SETPOINT
  local min_cooling_setpoint = device_scale == ThermostatSetpoint.scale.CELSIUS and f_to_c(MIN_COOLING_SETPOINT) or MIN_COOLING_SETPOINT
  local max_heating_setpoint = device_scale == ThermostatSetpoint.scale.CELSIUS and f_to_c(MAX_HEATING_SETPOINT) or MAX_HEATING_SETPOINT
  local max_cooling_setpoint = device_scale == ThermostatSetpoint.scale.CELSIUS and f_to_c(MAX_COOLING_SETPOINT) or MAX_COOLING_SETPOINT

  local min_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1) and min_heating_setpoint or min_cooling_setpoint
  local max_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1) and max_heating_setpoint or max_cooling_setpoint

  local deadband = (device_scale == ThermostatSetpoint.scale.FAHRENHEIT) and 3 or 2

  local comp_heating_setpoint = data.current_heating_setpoint ~= nil and data.current_heating_setpoint or 0
  local comp_cooling_setpoint = data.current_cooling_setpoint ~= nil and data.current_cooling_setpoint or 0

  local target_value = data.target_value
  local heating_setpoint = nil
  local cooling_setpoint = nil

  if target_value > max_setpoint then
    -- In case of heating_setpoint
    ---- heating_setpoint value is 92F
    ---- cooling_setpoint value is 95F
    -- In case of cooling_setpoint
    ---- heating_setpoint value is current heating_setpoint
    ---- cooling_setpoint value is 95F
    heating_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1) and max_setpoint or data.current_heating_setpoint
    cooling_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1) and max_setpoint + deadband or max_setpoint
  elseif target_value < min_setpoint then
    -- In case of heating_setpoint
    ---- heating_setpoint value is 38F
    ---- cooling_setpoint value is current cooling_setpoint
    -- In case of cooling_setpoint
    ---- heating_setpoint value is 35F
    ---- cooling_setpoint value is 38F
    heating_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1) and min_setpoint - deadband or min_setpoint
    cooling_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1) and min_setpoint or data.current_cooling_setpoint
  end

  if setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1 and cooling_setpoint == nil then
    heating_setpoint = target_value
    cooling_setpoint = (heating_setpoint + deadband > comp_cooling_setpoint) and heating_setpoint + deadband or nil
  end

  if setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1 and heating_setpoint == nil then
    cooling_setpoint = target_value
    heating_setpoint = (cooling_setpoint - deadband < comp_heating_setpoint) and cooling_setpoint - deadband or nil
  end

  return {target_heating_setpoint = heating_setpoint, target_cooling_setpoint = cooling_setpoint}
end

local function update_enforce_setpoint_limits(device, setpoint_type, value)
  local heating_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1) and value or device:get_field(CURRENT_HEATING_SETPOINT)
  local cooling_setpoint = (setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1) and value or device:get_field(CURRENT_COOLING_SETPOINT)

  local data = enforce_setpoint_limits(device, setpoint_type, {target_value = value, current_heating_setpoint = heating_setpoint, current_cooling_setpoint = cooling_setpoint})

  if setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1 and data.target_heating_setpoint then
    data.target_heating_setpoint = nil
  elseif setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1 and data.target_cooling_setpoint then
    data.target_cooling_setpoint = nil
  end

  if data.target_heating_setpoint ~= nil or data.target_cooling_setpoint ~= nil then
    send_setpoint_to_device(device, data)
  end
end

local function update_setpoints(device, setpoint_type, value)
  local scale = device:get_field(TEMPERATURE_SCALE)
  local heating_setpoint = device:get_field(CURRENT_HEATING_SETPOINT)
  local cooling_setpoint = device:get_field(CURRENT_COOLING_SETPOINT)
  local data = { target_heating_setpoint = nil, target_cooling_setpoint = nil }

  data = enforce_setpoint_limits(device, setpoint_type, {target_value = value, current_heating_setpoint = heating_setpoint, current_cooling_setpoint = cooling_setpoint})
  if setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1 then
    data.target_heating_setpoint = data.target_heating_setpoint and data.target_heating_setpoint or heating_setpoint
  end

  send_setpoint_to_device(device, data)
end

local function thermostat_setpoint_report_handler(self, device, cmd)
  if (cmd.args.setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1 or cmd.args.setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1) then
    local cmd_scale = (cmd.args.scale == ThermostatSetpoint.scale.FAHRENHEIT) and 'F' or 'C'
    local value = cmd.args.value
    local mode = device:get_field(MODE)

    device:set_field(TEMPERATURE_SCALE, cmd.args.scale, {persist = true})
    device:set_field(PRECISION, cmd.args.precision, {persist = true})

    if cmd.args.setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1 then
      local is_limited = device:get_field(HEATING_SETPOINT_IS_LIMITED)
      if is_limited then
        -- In case heating_setpoint is limited by enforce_setpoint_limits()
        device:set_field(HEATING_SETPOINT_IS_LIMITED, false, {persist = true})
        device:set_field(CURRENT_HEATING_SETPOINT, value, {persist = true})
        device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = value, unit = cmd_scale}))
      elseif mode ~= nil and mode ~= ThermostatMode.mode.COOL then
        -- In case heating_setpoint is changed by device
        update_enforce_setpoint_limits(device, ThermostatSetpoint.setpoint_type.HEATING_1, value)
      end
    elseif cmd.args.setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1 then
      local is_limited = device:get_field(COOLING_SETPOINT_IS_LIMITED)
      if is_limited then
        -- In case cooling_setpoint is limited by enforce_setpoint_limits()
        device:set_field(COOLING_SETPOINT_IS_LIMITED, false, {persist = true})
        device:set_field(CURRENT_COOLING_SETPOINT, value, {persist = true})
        device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = value, unit = cmd_scale}))
      elseif mode ~= nil and (mode ~= ThermostatMode.mode.HEAT or mode ~= ThermostatMode.mode.AUXILIARY_HEAT) then
        -- In case cooling_setpoint is changed by device
        update_enforce_setpoint_limits(device, ThermostatSetpoint.setpoint_type.COOLING_1, value)
      end
    end
  end
end

local function thermostat_mode_report_handler(self, device, cmd)
  local event = nil

  local mode = cmd.args.mode
  if mode == ThermostatMode.mode.OFF then
    event = capabilities.thermostatMode.thermostatMode.off()
  elseif mode == ThermostatMode.mode.HEAT then
    event = capabilities.thermostatMode.thermostatMode.heat()
  elseif mode == ThermostatMode.mode.COOL then
    event = capabilities.thermostatMode.thermostatMode.cool()
  elseif mode == ThermostatMode.mode.AUTO then
    event = capabilities.thermostatMode.thermostatMode.auto()
  elseif mode == ThermostatMode.mode.AUXILIARY_HEAT then
    event = capabilities.thermostatMode.thermostatMode.emergency_heat()
  end

  device:set_field(MODE, mode, {persist = true})

  if (event ~= nil) then
    device:emit_event(event)
  end

  local heating_setpoint = device:get_field(CURRENT_HEATING_SETPOINT)
  local cooling_setpoint = device:get_field(CURRENT_COOLING_SETPOINT)
  local current_temperature = device:get_field(TEMPERATURE)

  device:send(ThermostatOperatingState:Get({}))
  if mode == ThermostatMode.mode.COOL or
    ((mode == ThermostatMode.mode.COOL or mode == ThermostatMode.mode.OFF) and (current_temperature > (heating_setpoint + cooling_setpoint) / 2)) then
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
  else
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
  end
end

local function temperature_report_handler(self, device, cmd)
  if (cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE) then
    local scale = 'C'
    if (cmd.args.scale == SensorMultilevel.scale.temperature.FAHRENHEIT) then scale = 'F' end
    device:emit_event_for_endpoint(cmd.src_channel, capabilities.temperatureMeasurement.temperature({value = cmd.args.sensor_value, unit = scale}))
    device:set_field(TEMPERATURE, cmd.args.sensor_value, {persist = true})
  end
end

local function set_setpoint_factory(setpoint_type)
  return function(driver, device, command)
    update_setpoints(device, setpoint_type, command.args.setpoint)
  end
end

local ct100_thermostat = {
  NAME = "CT100 thermostat",
  zwave_handlers = {
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = temperature_report_handler
    },
    [cc.THERMOSTAT_SETPOINT] = {
      [ThermostatSetpoint.REPORT] = thermostat_setpoint_report_handler
    },
    [cc.THERMOSTAT_MODE] = {
      [ThermostatMode.REPORT] = thermostat_mode_report_handler
    }
  },
  capability_handlers = {
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint_factory(ThermostatSetpoint.setpoint_type.HEATING_1)
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint_factory(ThermostatSetpoint.setpoint_type.COOLING_1)
    }
  },
  can_handle = can_handle_ct100_thermostat,
}

return ct100_thermostat
