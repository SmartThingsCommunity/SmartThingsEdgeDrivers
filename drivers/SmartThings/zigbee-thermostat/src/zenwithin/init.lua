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
local log               = require "log"
local utils             = require "st.utils"

local clusters                      = require "st.zigbee.zcl.clusters"
local PowerConfiguration            = clusters.PowerConfiguration
local Thermostat                    = clusters.Thermostat
local FanControl                    = clusters.FanControl
local ThermostatControlSequence     = Thermostat.attributes.ControlSequenceOfOperation
local ThermostatSystemMode          = Thermostat.attributes.SystemMode

local capabilities                 = require "st.capabilities"
local ThermostatMode               = capabilities.thermostatMode
local ThermostatFanMode            = capabilities.thermostatFanMode
local ThermostatOperatingState     = capabilities.thermostatOperatingState
local ThermostatCoolingSetpoint    = capabilities.thermostatCoolingSetpoint
local ThermostatHeatingSetpoint    = capabilities.thermostatHeatingSetpoint
local Battery                      = capabilities.battery

local MIN_HEAT_LIMIT = "minHeatSetpoint"
local MAX_HEAT_LIMIT = "maxHeatSetpoint"
local MIN_COOL_LIMIT = "minCoolSetpoint"
local MAX_COOL_LIMIT = "maxCoolSetpoint"
local COOLING_SETPOINT = "coolingSetpoint"
local HEATING_SETPOINT = "heatingSetpoint"
local THERMOSTAT_SETPOINT = "thermostatSetpoint"

local BAT_MIN = 34.0 -- voltage when device UI starts to die, ie, when battery fails
local BAT_MAX = 60.0 -- 4 batteries at 1.5V (6.0V)

local DEFAULT_MIN_SETPOINT = 4.0
local DEFAULT_MAX_SETPOINT = 37.5

-- In zenwithin sub driver, supported thermostat mode follow preference option because sensor always returns 'all mode possible'
local SUPPORTED_THERMOSTAT_MODES = {
  [0x01] = { "off", "heat" },
  [0x02] = { "off", "cool" },
  [0x03] = { "off", "heat", "cool" }, --default
  [0x04] = { "off", "auto", "heat", "cool" },
  [0x05] = { "off", "emergency heat", "heat", "cool" }
}

local THERMOSTAT_SYSTEM_MODE_MAP = {
  [ThermostatSystemMode.OFF]               = ThermostatMode.thermostatMode.off,
  [ThermostatSystemMode.AUTO]              = ThermostatMode.thermostatMode.auto,
  [ThermostatSystemMode.COOL]              = ThermostatMode.thermostatMode.cool,
  [ThermostatSystemMode.HEAT]              = ThermostatMode.thermostatMode.heat,
  [ThermostatSystemMode.EMERGENCY_HEATING] = ThermostatMode.thermostatMode.emergency_heat,
  [ThermostatSystemMode.FAN_ONLY]          = ThermostatMode.thermostatMode.fanonly
}

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, FanControl.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 5, 300, 50)) -- report temperature changes over 0.5°C
  device:send(Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(device, 5, 300, 50))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 5, 300, 50))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 5, 300))
  device:send(Thermostat.attributes.ThermostatRunningMode:configure_reporting(device, 5, 300))
  device:send(Thermostat.attributes.ThermostatRunningState:configure_reporting(device, 5, 300))
  device:send(FanControl.attributes.FanMode:configure_reporting(device, 5, 300))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_THERMOSTAT_MODES[3]))-- default: { "off", "heat", "cool" }
end

local battery_voltage_handler = function(driver, device, battery_voltage)
  local perc_value = utils.round((battery_voltage.value - BAT_MIN)/(BAT_MAX - BAT_MIN) * 100)
  if (perc_value < 100) then
    device:emit_event(Battery.battery(utils.clamp_value(perc_value, 0, 100)))
  else
    device:emit_event(Battery.battery(100))
  end
end

local supported_thermostat_modes_handler = function(driver, device, supported_modes)
  -- Zen thermostat used to return a value of 0x04 "All modes are possible",
  -- regardless of configuration on the thermostat thus instead of polling this, Driver will use user configurable settings instead.
end

local update_thermostat_setpoint = function(device)
  local modes = ThermostatMode.thermostatMode
  local setpoint = nil
  local heating_setpoint = device:get_latest_state("main", ThermostatHeatingSetpoint.ID, ThermostatHeatingSetpoint.heatingSetpoint.NAME)
  local cooling_setpoint = device:get_latest_state("main", ThermostatCoolingSetpoint.ID, ThermostatCoolingSetpoint.coolingSetpoint.NAME)
  local current_mode = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME)
  if (current_mode == modes.heat.NAME) then
    setpoint = heating_setpoint
  elseif (current_mode == modes.cool.NAME) then
    setpoint = cooling_setpoint
  elseif (current_mode == modes.auto.NAME or current_mode == modes.off.NAME) then
    if (heating_setpoint ~= nil and cooling_setpoint ~= nil) then
      setpoint = (heating_setpoint + cooling_setpoint) / 2
    end
  end
  if setpoint then
    device:set_field(THERMOSTAT_SETPOINT, setpoint, {persist = true})
  end
end

local thermostat_mode_handler = function(driver, device, thermostat_mode)
  if THERMOSTAT_SYSTEM_MODE_MAP[thermostat_mode.value] then
    local current_supported_modes = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.supportedThermostatModes.NAME)
    if current_supported_modes then
      device:emit_event(THERMOSTAT_SYSTEM_MODE_MAP[thermostat_mode.value]({data = {supportedThermostatModes = current_supported_modes}}))
    else
      device:emit_event(THERMOSTAT_SYSTEM_MODE_MAP[thermostat_mode.value]())
    end
  end
  device.thread:call_with_delay(10, function(d) update_thermostat_setpoint(device) end)
end

local setpoint_limit_handler = function(limit_type)
  return function(driver, device, limit)
    device:set_field(limit_type, limit.value, {persist = true})
  end
end

local thermostat_cooling_setpoint_handler = function(driver, device, setpoint)
  local raw_temp = setpoint.value
  local celc_temp = raw_temp / 100.0
  local temp_scale = "C"
  device:emit_event(ThermostatCoolingSetpoint.coolingSetpoint({value = celc_temp, unit = temp_scale}))
  device.thread:call_with_delay(5, function(d) update_thermostat_setpoint(device) end)
end

local thermostat_heating_setpoint_handler = function(driver, device, setpoint)
  local raw_temp = setpoint.value
  local celc_temp = raw_temp / 100.0
  local temp_scale = "C"
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = celc_temp, unit = temp_scale}))
  device.thread:call_with_delay(5, function(d) update_thermostat_setpoint(device) end)
end

local contains = function(input, val)
  for _, value in ipairs(input) do
    if value == val then
      return true
    end
  end
  return false
end

local set_thermostat_mode = function(driver, device, command)
  local next_mode = command.args.mode
  local current_supported_modes = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.supportedThermostatModes.NAME)
  if (contains(current_supported_modes, next_mode)) then
    local setpoint = device:get_field(THERMOSTAT_SETPOINT)
    local heating_setpoint = nil
    local cooling_setpoint = nil

    if (next_mode == "heat" or next_mode == "emergency heat") then
      heating_setpoint = setpoint
    elseif (next_mode == "cool") then
      cooling_setpoint = setpoint
    else -- off, auto
      local current_mode = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME)
      if (current_mode ~= "off" and current_mode ~= "auto") then
        heating_setpoint = setpoint - 2
        cooling_setpoint = setpoint + 2
      end
    end

    if (heating_setpoint ~= nil) then
      device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, heating_setpoint*100))
    end

    if (cooling_setpoint ~= nil) then
      device:send(Thermostat.attributes.OccupiedCoolingSetpoint:write(device, cooling_setpoint*100))
    end

    for zigbee_attr_val, st_cap_val in pairs(THERMOSTAT_SYSTEM_MODE_MAP) do
      if next_mode == st_cap_val.NAME then
        device:send(Thermostat.attributes.SystemMode:write(device, zigbee_attr_val))
        break
      end
    end
  else
    log.warn("The next mode[" .. next_mode .. "] is not supported mode")
  end
end

local thermostat_mode_setter = function(mode_name)
  return function(driver, device, command)
    set_thermostat_mode(driver, device, {args={mode=mode_name}})
  end
end

local update_device_setpoint = function(device)
  local target_value = nil
  local heating_setpoint = device:get_field(HEATING_SETPOINT)
  local cooling_setpoint = device:get_field(COOLING_SETPOINT)
  if (heating_setpoint ~= nil and cooling_setpoint ~= nil) then
    target_value = (heating_setpoint + cooling_setpoint ) / 2
  elseif (heating_setpoint ~= nil) then
    target_value = heating_setpoint
  elseif (cooling_setpoint ~= nil) then
    target_value = cooling_setpoint
  else
    target_value = device:get_field(THERMOSTAT_SETPOINT)
  end

  heating_setpoint = nil
  cooling_setpoint = nil
  device:set_field(HEATING_SETPOINT, nil)
  device:set_field(COOLING_SETPOINT, nil)

  local min_setpoint = DEFAULT_MIN_SETPOINT
  local max_setpoint = DEFAULT_MAX_SETPOINT
  local current_mode = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME)
  if (current_mode == "auto") then
    if (device:get_field(MIN_HEAT_LIMIT) ~= nil) then
      min_setpoint = device:get_field(MIN_HEAT_LIMIT)
    end
    if (device:get_field(MAX_COOL_LIMIT) ~= nil) then
      max_setpoint = device:get_field(MAX_COOL_LIMIT)
    end
    target_value = utils.clamp_value(target_value, min_setpoint, max_setpoint)
    heating_setpoint = target_value - 2
    cooling_setpoint = target_value + 2
    if (heating_setpoint < min_setpoint) then
      cooling_setpoint = cooling_setpoint - (min_setpoint - heating_setpoint)
      heating_setpoint = min_setpoint
      target_value = (heating_setpoint + cooling_setpoint) / 2
    end
    if (cooling_setpoint > max_setpoint) then
      if (cooling_setpoint < max_setpoint + 2) then
        heating_setpoint = heating_setpoint + (cooling_setpoint - max_setpoint)
      else
        heating_setpoint = max_setpoint - 0.5
      end
    end
  elseif (current_mode == "heat" or current_mode == "emergency heat") then
    if (device:get_field(MIN_HEAT_LIMIT) ~= nil) then
      min_setpoint = device:get_field(MIN_HEAT_LIMIT)
    end
    if (device:get_field(MAX_HEAT_LIMIT) ~= nil) then
      max_setpoint = device:get_field(MAX_HEAT_LIMIT)
    end
    heating_setpoint = utils.clamp_value(target_value, min_setpoint, max_setpoint)
  elseif (current_mode == "cool") then
    if (device:get_field(MIN_COOL_LIMIT) ~= nil) then
      min_setpoint = device:get_field(MIN_COOL_LIMIT)
    end
    if (device:get_field(MAX_COOL_LIMIT) ~= nil) then
      max_setpoint = device:get_field(MAX_COOL_LIMIT)
    end
    cooling_setpoint = utils.clamp_value(target_value, min_setpoint, max_setpoint)
  else -- "off"
    -- do nothing, don't allow change of setpoint in off mode
    target_value = nil
  end

  if (heating_setpoint ~= nil) then
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, heating_setpoint*100))
  end

  if (cooling_setpoint ~= nil) then
    device:send(Thermostat.attributes.OccupiedCoolingSetpoint:write(device, cooling_setpoint*100))
  end
end

local set_cooling_setpoint = function(driver, device, command)
  local current_mode = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME)
  if (current_mode == "cool" or current_mode == "auto") then
    local value = command.args.setpoint
    if value >= 40 then -- we got a command in fahrenheit
      value = utils.f_to_c(value)
    end
    device:set_field(COOLING_SETPOINT, value)
    device.thread:call_with_delay(2, function(d) update_device_setpoint(device) end)
  else
    local cooling_setpoint = device:get_latest_state("main", ThermostatCoolingSetpoint.ID, ThermostatCoolingSetpoint.coolingSetpoint.NAME)
    if (cooling_setpoint ~= nil) then
      device:emit_event(ThermostatCoolingSetpoint.coolingSetpoint({value = cooling_setpoint, unit = "C"}))
    end
  end
end

local set_heating_setpoint = function(driver, device, command)
  local current_mode = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME)
  if (current_mode ~= "cool" and current_mode ~= "auto") then
    local value = command.args.setpoint
    if value >= 40 then -- we got a command in fahrenheit
      value = utils.f_to_c(value)
    end
    device:set_field(HEATING_SETPOINT, value)
    device.thread:call_with_delay(2, function(d) update_device_setpoint(device) end)
  else
    local heating_setpoint = device:get_latest_state("main", ThermostatHeatingSetpoint.ID, ThermostatHeatingSetpoint.heatingSetpoint.NAME)
    if (heating_setpoint ~= nil) then
      device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = heating_setpoint, unit = "C"}))
    end
  end
end

local function info_changed(driver, device, event, args)
  local modes_index = tonumber(device.preferences.systemModes)
  local new_supported_modes = SUPPORTED_THERMOSTAT_MODES[modes_index]
  device:emit_event(ThermostatMode.supportedThermostatModes(new_supported_modes))
end

local zenwithin_thermostat = {
  NAME = "Zenwithin Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler,
        [Thermostat.attributes.ThermostatRunningMode.ID] = thermostat_mode_handler,
        [Thermostat.attributes.SystemMode.ID] = thermostat_mode_handler,
        [Thermostat.attributes.MinHeatSetpointLimit.ID] = setpoint_limit_handler(MIN_HEAT_LIMIT),
        [Thermostat.attributes.MaxHeatSetpointLimit.ID] = setpoint_limit_handler(MAX_HEAT_LIMIT),
        [Thermostat.attributes.MinCoolSetpointLimit.ID] = setpoint_limit_handler(MIN_COOL_LIMIT),
        [Thermostat.attributes.MaxCoolSetpointLimit.ID] = setpoint_limit_handler(MAX_COOL_LIMIT),
        [Thermostat.attributes.OccupiedCoolingSetpoint.ID] = thermostat_cooling_setpoint_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_setpoint_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_voltage_handler
      }
    }
  },
  capability_handlers = {
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [ThermostatMode.commands.auto.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.auto.NAME),
      [ThermostatMode.commands.off.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.off.NAME),
      [ThermostatMode.commands.cool.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.cool.NAME),
      [ThermostatMode.commands.heat.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.heat.NAME),
      [ThermostatMode.commands.emergencyHeat.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.emergency_heat.NAME)
    },
    [ThermostatCoolingSetpoint.ID] = {
      [ThermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_cooling_setpoint
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Zen Within" and device:get_model() == "Zen-01"
  end
}

return zenwithin_thermostat
