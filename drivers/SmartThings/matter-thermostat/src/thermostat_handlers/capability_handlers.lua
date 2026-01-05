-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local log = require "log"
local version = require "version"
local st_utils = require "st.utils"
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local fields = require "thermostat_utils.fields"
local thermostat_utils = require "thermostat_utils.utils"

if version.api < 10 then
  clusters.HepaFilterMonitoring = require "embedded_clusters.HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "embedded_clusters.ActivatedCarbonFilterMonitoring"
end

if version.api < 13 then
  clusters.WaterHeaterMode = require "embedded_clusters.WaterHeaterMode"
end

local CapabilityHandlers = {}


-- [[ FAN SPEED PERCENT CAPABILITY HANDLERS ]] --

function CapabilityHandlers.handle_fan_speed_set_percent(driver, device, cmd)
  local speed = math.floor(cmd.args.percent)
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, thermostat_utils.component_to_endpoint(device, cmd.component, clusters.FanControl.ID), speed))
end


-- [[ WIND MODE CAPABILITY HANDLERS ]] --

function CapabilityHandlers.handle_set_wind_mode(driver, device, cmd)
  local wind_mode = 0
  if cmd.args.windMode == capabilities.windMode.windMode.sleepWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.SLEEP_WIND
  elseif cmd.args.windMode == capabilities.windMode.windMode.naturalWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.NATURAL_WIND
  end
  device:send(clusters.FanControl.attributes.WindSetting:write(device, thermostat_utils.component_to_endpoint(device, cmd.component, clusters.FanControl.ID), wind_mode))
end


-- [[ FAN OSCILLATION MODE HANDLERS ]] --

function CapabilityHandlers.handle_set_fan_oscillation_mode(driver, device, cmd)
  local rock_mode = 0
  if cmd.args.fanOscillationMode == capabilities.fanOscillationMode.fanOscillationMode.horizontal.NAME then
    rock_mode = clusters.FanControl.types.RockSupportMask.ROCK_LEFT_RIGHT
  elseif cmd.args.fanOscillationMode == capabilities.fanOscillationMode.fanOscillationMode.vertical.NAME then
    rock_mode = clusters.FanControl.types.RockSupportMask.ROCK_UP_DOWN
  elseif cmd.args.fanOscillationMode == capabilities.fanOscillationMode.fanOscillationMode.swing.NAME then
    rock_mode = clusters.FanControl.types.RockSupportMask.ROCK_ROUND
  end
  device:send(clusters.FanControl.attributes.RockSetting:write(device, thermostat_utils.component_to_endpoint(device, cmd.component, clusters.FanControl.ID), rock_mode))
end


-- [[ MODE CAPABILITY HANDLERS ]] --

function CapabilityHandlers.handle_set_mode(driver, device, cmd)
  device.log.info(string.format("set_water_heater_mode mode: %s", cmd.args.mode))
  local endpoint_id = thermostat_utils.component_to_endpoint(device, cmd.component, clusters.Thermostat.ID)
  local supportedWaterHeaterModesWithIdx = device:get_field(fields.SUPPORTED_WATER_HEATER_MODES_WITH_IDX) or {}
  for i, mode in ipairs(supportedWaterHeaterModesWithIdx) do
    if cmd.args.mode == mode[2] then
      device:send(clusters.WaterHeaterMode.commands.ChangeToMode(device, endpoint_id, mode[1]))
      return
    end
  end
end


-- [[ FILTER STATE CAPABLITY HANDLERS ]] --

function CapabilityHandlers.handle_filter_state_reset_filter(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  if cmd.component == "hepaFilter" then
    device:send(clusters.HepaFilterMonitoring.server.commands.ResetCondition(device, endpoint_id))
  else
    device:send(clusters.ActivatedCarbonFilterMonitoring.server.commands.ResetCondition(device, endpoint_id))
  end
end


-- [[ SWITCH CAPABLITY HANDLERS ]] --

function CapabilityHandlers.handle_switch_on(driver, device, cmd)
  local endpoint_id = thermostat_utils.component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

function CapabilityHandlers.handle_switch_off(driver, device, cmd)
  local endpoint_id = thermostat_utils.component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end


-- [[ THERMOSTAT MODE CAPABLITY HANDLERS ]] --

function CapabilityHandlers.handle_set_thermostat_mode(driver, device, cmd)
  local mode_id = nil
  for value, mode in pairs(fields.THERMOSTAT_MODE_MAP) do
    if mode.NAME == cmd.args.mode then
      mode_id = value
      break
    end
  end
  if mode_id then
    device:send(clusters.Thermostat.attributes.SystemMode:write(device, thermostat_utils.component_to_endpoint(device, cmd.component, clusters.Thermostat.ID), mode_id))
  end
end

function CapabilityHandlers.thermostat_mode_command_factory(mode_name)
  return function(driver, device, cmd)
    return CapabilityHandlers.handle_set_thermostat_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
  end
end


-- [[ <DEVICE TYPE> FAN MODE CAPABILITY HANDLERS ]] --

local function set_fan_mode(device, cmd, fan_mode_capability)
  local command_argument = cmd.args.fanMode
  if fan_mode_capability == capabilities.airPurifierFanMode then
    command_argument = cmd.args.airPurifierFanMode
  elseif fan_mode_capability == capabilities.thermostatFanMode then
    command_argument = cmd.args.mode
  end
  local fan_mode_id
  if command_argument == "off" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  elseif command_argument == "on" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.ON
  elseif command_argument == "auto" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  elseif command_argument == "high" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif command_argument == "medium" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif thermostat_utils.tbl_contains({ "low", "sleep", "quiet", "windFree" }, command_argument) then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  else
    device.log.warn(string.format("Invalid Fan Mode (%s) received from capability command", command_argument))
    return
  end
  device:send(clusters.FanControl.attributes.FanMode:write(device, thermostat_utils.component_to_endpoint(device, cmd.component, clusters.FanControl.ID), fan_mode_id))
end

function CapabilityHandlers.fan_mode_command_factory(fan_mode_capability)
  return function(driver, device, cmd)
    set_fan_mode(device, cmd, fan_mode_capability)
  end
end


-- [[ THERMOSTAT FAN MODE CAPABILITY HANDLERS ]] --

function CapabilityHandlers.thermostat_fan_mode_command_factory(mode_name)
  return function(driver, device, cmd)
    set_fan_mode(device, {component = cmd.component, args = {mode = mode_name}}, capabilities.thermostatFanMode)
  end
end


-- [[ THERMOSTAT HEATING/COOLING CAPABILITY HANDLERS ]] --

function CapabilityHandlers.thermostat_set_setpoint_factory(setpoint)
  return function(driver, device, cmd)
    local endpoint_id = thermostat_utils.component_to_endpoint(device, cmd.component, clusters.Thermostat.ID)
    local MAX_TEMP_IN_C = fields.THERMOSTAT_MAX_TEMP_IN_C
    local MIN_TEMP_IN_C = fields.THERMOSTAT_MIN_TEMP_IN_C
    local is_water_heater_device = thermostat_utils.get_device_type(device) == fields.WATER_HEATER_DEVICE_TYPE_ID
    if is_water_heater_device then
      MAX_TEMP_IN_C = fields.WATER_HEATER_MAX_TEMP_IN_C
      MIN_TEMP_IN_C = fields.WATER_HEATER_MIN_TEMP_IN_C
    end
    local value = cmd.args.setpoint
    if version.rpc <= 5 and value > MAX_TEMP_IN_C then
      value = st_utils.f_to_c(value)
    end

    -- Gather cached setpoint values when considering setpoint limits
    -- Note: cached values should always exist, but defaults are chosen just in case to prevent
    -- nil operation errors, and deadband logic from triggering.
    local cached_cooling_val, cooling_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatCoolingSetpoint.ID,
      capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME,
      MAX_TEMP_IN_C, { value = MAX_TEMP_IN_C, unit = "C" }
    )
    if cooling_setpoint and cooling_setpoint.unit == "F" then
      cached_cooling_val = st_utils.f_to_c(cached_cooling_val)
    end
    local cached_heating_val, heating_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatHeatingSetpoint.ID,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME,
      MIN_TEMP_IN_C, { value = MIN_TEMP_IN_C, unit = "C" }
    )
    if heating_setpoint and heating_setpoint.unit == "F" then
      cached_heating_val = st_utils.f_to_c(cached_heating_val)
    end
    local is_auto_capable = #device:get_endpoints(
      clusters.Thermostat.ID,
      {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE}
    ) > 0

    --Check setpoint limits for the device
    local setpoint_type = string.match(setpoint.NAME, "Heat") or "Cool"
    local deadband = device:get_field(fields.setpoint_limit_device_field.MIN_DEADBAND) or 2.5 --spec default
    if setpoint_type == "Heat" then
      local min = device:get_field(fields.setpoint_limit_device_field.MIN_HEAT) or MIN_TEMP_IN_C
      local max = device:get_field(fields.setpoint_limit_device_field.MAX_HEAT) or MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value > (cached_cooling_val - deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is greater than the cooling setpoint (%s) with the deadband (%s)",
          value, cooling_setpoint, deadband
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
    else
      local min = device:get_field(fields.setpoint_limit_device_field.MIN_COOL) or MIN_TEMP_IN_C
      local max = device:get_field(fields.setpoint_limit_device_field.MAX_COOL) or MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value < (cached_heating_val + deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is less than the heating setpoint (%s) with the deadband (%s)",
          value, heating_setpoint, deadband
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
    end
    device:send(setpoint:write(device, thermostat_utils.component_to_endpoint(device, cmd.component, clusters.Thermostat.ID), st_utils.round(value * 100.0)))
  end
end

return CapabilityHandlers
