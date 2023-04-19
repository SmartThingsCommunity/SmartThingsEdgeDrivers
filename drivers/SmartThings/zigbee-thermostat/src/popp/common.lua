-- Zigbee driver utilities
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"
local log = require "log"

-- Zigbee specific cluster
local clusters = require "st.zigbee.zcl.clusters"
local Thermostat = clusters.Thermostat

-- Capabilities
local capabilities = require "st.capabilities"
local ThermostatMode = capabilities.thermostatMode
local TemperatureAlarm = capabilities.temperatureAlarm
local Switch = capabilities.switch
local TemperatureMeasurement = capabilities.temperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint

local last_setpointTemp = nil
local common = {}

common.MIN_SETPOINT = 5
common.MAX_SETPOINT = 30
common.STORED_HEAT_MODE = "stored_heat_mode"

common.THERMOSTAT_CLUSTER_ID = 0x0201
common.MFG_CODE = 0x1246
common.WINDOW_OPEN_FEATURE = nil

common.THERMOSTAT_SETPOINT_CMD_ID = 0x40
common.WINDOW_OPEN_DETECTION_ID = 0x4000
common.WINDOW_OPEN_DETECTION_MAP = {
  [0x00] = "cleared", -- // "quarantine" default
  [0x01] = "cleared", -- // "closed" window is closed
  [0x02] = "freeze", -- // "hold" window might be opened
  [0x03] = "freeze", -- // "opened" window is opened
  [0x04] = "freeze", -- // "opened_alarm" a closed window was opened externally (=alert)
}
common.EXTERNAL_OPEN_WINDOW_DETECTION_ID = 0x4003

local SUPPORTED_MODES = {
  ThermostatMode.thermostatMode.off.NAME,
  ThermostatMode.thermostatMode.heat.NAME,
  ThermostatMode.thermostatMode.eco.NAME
}

-- Helpers

-- has member check function
local has_member = function(haystack, needle)
  for _, value in ipairs(haystack) do
    if (value == needle) then
      return true
    end
  end
  return false
end

-- Turn switch 'on' if its state is 'off'
local turn_switch_on = function(driver, device)
  -- turn thermostat ventile on
  if device:get_latest_state("main", Switch.ID, Switch.switch.NAME) == "off" then
    common.switch_handler_factory('on')(driver, device)
  end
end

-- Handlers

-- Internal window open detection handler
common.window_open_detection_handler = function(driver, device, value, zb_rx)
  device:emit_event(TemperatureAlarm.temperatureAlarm(common.WINDOW_OPEN_DETECTION_MAP[value.value]))
end

-- Switch handler
common.switch_handler_factory = function(switch_state)
  return function(driver, device, cmd)
    local get_cmd = switch_state or cmd.command
    local external_window_open

    if get_cmd == 'on' then
      external_window_open = false
    elseif get_cmd == 'off' then
      external_window_open = true
    end

    device:send(cluster_base.write_manufacturer_specific_attribute(device, common.THERMOSTAT_CLUSTER_ID,
      common.EXTERNAL_OPEN_WINDOW_DETECTION_ID,
      common.MFG_CODE, data_types.Boolean, external_window_open))
  end
end

-- Custom setpoint command handler
common.setpoint_cmd_handler = function(driver, device, cmd)
  local payload
  local mode = cmd.args.mode

  if has_member(SUPPORTED_MODES, mode) then

    -- fetch last_setpointTemp
    last_setpointTemp = device:get_field("last_setpointTemp")

    if last_setpointTemp == nil then
      last_setpointTemp = device:get_latest_state("main", ThermostatHeatingSetpoint.ID, ThermostatHeatingSetpoint.heatingSetpoint.NAME) or 21 -- thermostat default temperature
    end

    -- prepare setpoint for correct 4 char dec format
    last_setpointTemp = math.floor(last_setpointTemp * 100)

    -- convert setpoint value into bytes e.g. 25.5 -> 2550 -> \x09\xF6 -> \xF6\x09
    local s = string.format("%04X", tostring(last_setpointTemp))
    local p2 = tonumber(string.sub(s, 3, 4), 16)
    local p3 = tonumber(string.sub(s, 1, 2), 16)
    local type = nil

    if mode == ThermostatMode.thermostatMode.heat.NAME then
      -- Setpoint type "1": the actuator will make a large movement to minimize reaction time to UI
      type = 0x01
    elseif mode == ThermostatMode.thermostatMode.eco.NAME then
      -- Setpoint type "0": the behavior will be the same as setting the attribute "Occupied Heating Setpoint" to the same value
      type = 0x00
    end

    -- send thermostat setpoint command
    payload = string.char(type, p2, p3)
    device:send(cluster_base.build_manufacturer_specific_command(device, common.THERMOSTAT_CLUSTER_ID,
    common.THERMOSTAT_SETPOINT_CMD_ID, common.MFG_CODE, payload))

    -- turn thermostat ventile on
    turn_switch_on(driver, device)

    device:set_field(common.STORED_HEAT_MODE, mode)
    device:emit_event(ThermostatMode.thermostatMode[mode]())

  else
    -- Generate event for the mobile client if it is calling us
    device:emit_event(ThermostatMode.thermostatMode(device:get_latest_state("main", ThermostatMode.ID,
      ThermostatMode.thermostatMode.NAME)))
  end
end

-- temperature setpoint handler
common.handle_set_setpoint = function(driver, device, command)
  local value = command.args.setpoint

  -- fetch and set latest setpoint for heat mode
  common.last_setpointTemp = device:get_field("last_setpointTemp")

  if value ~= common.last_setpointTemp then
    device:set_field("last_setpointTemp", value)
  end

  -- write new setpoint
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, value * 100))

  -- turn thermostat ventile on
  turn_switch_on(driver, device)

  -- read setpoint
  device.thread:call_with_delay(2, function(d)
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  end)
end

-- handle temperature
common.thermostat_local_temp_attr_handler = function(driver, device, value, zb_rx)
  local temperature = value.value
  local last_temp = device:get_latest_state("main", TemperatureMeasurement.ID,
    TemperatureMeasurement.temperature.NAME)
  local use_last = nil

  -- fetch invalid temperature
  if (temperature == 0x8000 or temperature == -32768) then
    if (last_temp ~= nil) then
      -- use last temperature instead
      temperature = last_temp
      use_last = "set"
    else
      log.error("Sensor Temperature: INVALID VALUE")
      return
    end
  -- Handle negative C (< 32F) readings
  elseif (temperature > 0x8000) then
    temperature = -(utils.round(2 * (65536 - temperature)) / 2)
  end

  if (use_last == nil) then
    temperature = temperature / 100
  end

  device:emit_event(TemperatureMeasurement.temperature({ value = temperature, unit = "C" }))
end

-- handle heating setpoint
common.thermostat_heating_set_point_attr_handler = function(driver, device, value, zb_rx)
  local point_value = value.value
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({ value = point_value / 100, unit = "C" }))

  -- turn thermostat ventile on
  turn_switch_on(driver, device)
end

-- handle external window open detection
common.external_open_window_detection_handler = function(driver, device, value, zb_rx)
  local last_switch_state = device:get_latest_state("main", Switch.ID, Switch.switch.NAME)
  local bool_state = nil

  if last_switch_state == 'on' then
    bool_state = false
  elseif last_switch_state == 'off' then
    bool_state = true
  end

  if bool_state ~= value.value then
    if value.value == false then
      device:emit_event(Switch.switch.on())
    else
      device:emit_event(Switch.switch.off())
    end
  end
end

return common