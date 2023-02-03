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
local utils             = require "st.utils"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local clusters                      = require "st.zigbee.zcl.clusters"
local PowerConfiguration            = clusters.PowerConfiguration
local Thermostat                    = clusters.Thermostat
local FanControl                    = clusters.FanControl
local ThermostatSystemMode          = Thermostat.attributes.SystemMode

local capabilities                 = require "st.capabilities"
local ThermostatMode               = capabilities.thermostatMode
local ThermostatCoolingSetpoint    = capabilities.thermostatCoolingSetpoint
local ThermostatHeatingSetpoint    = capabilities.thermostatHeatingSetpoint
local ModeAttribute                = ThermostatMode.thermostatMode

local MIN_HEAT_LIMIT = "minHeatSetpoint"
local MAX_HEAT_LIMIT = "maxHeatSetpoint"
local MIN_COOL_LIMIT = "minCoolSetpoint"
local MAX_COOL_LIMIT = "maxCoolSetpoint"
local COOLING_SETPOINT = "coolingSetpoint"
local HEATING_SETPOINT = "heatingSetpoint"

local BAT_MIN = 3.4 -- voltage when device UI starts to die, ie, when battery fails
local BAT_MAX = 6.0 -- 4 batteries at 1.5V (6.0V)

local DEFAULT_MIN_SETPOINT = 4.0
local DEFAULT_MAX_SETPOINT = 37.5

-- In zenwithin sub driver, supported thermostat mode follow preference option because sensor always returns 'all mode possible'
local SUPPORTED_THERMOSTAT_MODES = {
  [0x01] = { ModeAttribute.off.NAME, ModeAttribute.heat.NAME },
  [0x02] = { ModeAttribute.off.NAME, ModeAttribute.cool.NAME },
  [0x03] = { ModeAttribute.off.NAME, ModeAttribute.heat.NAME, ModeAttribute.cool.NAME }, --default
  [0x04] = { ModeAttribute.off.NAME, ModeAttribute.auto.NAME, ModeAttribute.heat.NAME, ModeAttribute.cool.NAME },
  [0x05] = { ModeAttribute.off.NAME, ModeAttribute.emergency_heat.NAME, ModeAttribute.heat.NAME, ModeAttribute.cool.NAME }
}

local THERMOSTAT_SYSTEM_MODE_MAP = {
  [ThermostatSystemMode.OFF]               = ModeAttribute.off,
  [ThermostatSystemMode.AUTO]              = ModeAttribute.auto,
  [ThermostatSystemMode.COOL]              = ModeAttribute.cool,
  [ThermostatSystemMode.HEAT]              = ModeAttribute.heat,
  [ThermostatSystemMode.EMERGENCY_HEATING] = ModeAttribute.emergency_heat,
  [ThermostatSystemMode.FAN_ONLY]          = ModeAttribute.fanonly
}

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, FanControl.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 5, 300, 50)) -- report temperature changes over 0.5°C
  device:send(Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(device, 5, 300, 50))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 5, 300, 50))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 5, 300))
  device:send(Thermostat.attributes.ThermostatRunningState:configure_reporting(device, 5, 300))
  device:send(FanControl.attributes.FanMode:configure_reporting(device, 5, 300))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_THERMOSTAT_MODES[3], { visibility = { displayed = false } }))-- default: { ModeAttribute.off.NAME, ModeAttribute.heat.NAME, ModeAttribute.cool.NAME }
end

local supported_thermostat_modes_handler = function(driver, device, supported_modes)
  -- Zen thermostat used to return a value of 0x04 "All modes are possible",
  -- regardless of configuration on the thermostat thus instead of polling this, Driver will use user configurable settings instead.
end

local setpoint_limit_handler = function(limit_type)
  return function(driver, device, limit)
    device:set_field(limit_type, limit.value, {persist = true})
  end
end

-- Set heating setpoint -> wait 2 seconds
--  -> if in heat mode, set heating setpoint
-- Set cooling setpoint -> wait 2 seconds
--  -> if in cool mode, set cooling setpoint
-- Set heating and cooling setpoint
--  -> if in auto mode, set both setpoints
--  -> if in heating mode, set heat
--  -> if in cooling mode, set cool

local update_device_setpoint = function(device)
  local heating_setpoint = device:get_field(HEATING_SETPOINT)
  local cooling_setpoint = device:get_field(COOLING_SETPOINT)

  device:set_field(HEATING_SETPOINT, nil)
  device:set_field(COOLING_SETPOINT, nil)

  local current_mode = device:get_latest_state("main", ThermostatMode.ID, ModeAttribute.NAME)
  if (current_mode == ModeAttribute.heat.NAME or current_mode == ModeAttribute.emergency_heat.NAME) and
      cooling_setpoint ~= nil then
    cooling_setpoint = device:get_latest_state("main", ThermostatCoolingSetpoint.ID, ThermostatCoolingSetpoint.coolingSetpoint.NAME)
    -- tried to set cooling setpoint while device was in heat mode
    device:emit_event(ThermostatCoolingSetpoint.coolingSetpoint({value = cooling_setpoint, unit = "C"}))
    cooling_setpoint = nil
  elseif (current_mode == ModeAttribute.cool.NAME) and heating_setpoint ~= nil then
    heating_setpoint = device:get_latest_state("main", ThermostatHeatingSetpoint.ID, ThermostatHeatingSetpoint.heatingSetpoint.NAME)
    device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = heating_setpoint, unit = "C"}))
    heating_setpoint = nil
  elseif (current_mode == ModeAttribute.off.NAME) then
    -- do nothing, don't allow change of setpoint in off mode
    heating_setpoint = nil
    cooling_setpoint = nil
  end

  if (heating_setpoint ~= nil) then
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, utils.round(heating_setpoint*100)))
  end

  if (cooling_setpoint ~= nil) then
    device:send(Thermostat.attributes.OccupiedCoolingSetpoint:write(device, utils.round(cooling_setpoint*100)))
  end
end

local set_cooling_setpoint = function(driver, device, command)
  local value = command.args.setpoint
  if value >= 40 then -- we got a command in fahrenheit
    value = utils.f_to_c(value)
  end
  value = utils.clamp_value(value,
    device:get_field(MIN_HEAT_LIMIT) or DEFAULT_MIN_SETPOINT,
    device:get_field(MAX_HEAT_LIMIT) or DEFAULT_MAX_SETPOINT)
  device:set_field(COOLING_SETPOINT, value)
  local current_mode = device:get_latest_state("main", ThermostatMode.ID, ModeAttribute.NAME)
  if current_mode == ModeAttribute.cool.NAME or current_mode == ModeAttribute.auto.NAME then
    -- if we're already in the right mode, update immediately
    update_device_setpoint(device)
  else
    -- the intention here is that the mode update handler should have already called this,
    -- this call is essentially a 10s backstop timeout on a setpoint set
    device.thread:call_with_delay(10, function(d) update_device_setpoint(device) end)
  end
end

local set_heating_setpoint = function(driver, device, command)
  local value = command.args.setpoint
  if value >= 40 then -- we got a command in fahrenheit
    value = utils.f_to_c(value)
  end
  value = utils.clamp_value(value,
    device:get_field(MIN_HEAT_LIMIT) or DEFAULT_MIN_SETPOINT,
    device:get_field(MAX_HEAT_LIMIT) or DEFAULT_MAX_SETPOINT)
  device:set_field(HEATING_SETPOINT, value)
  local current_mode = device:get_latest_state("main", ThermostatMode.ID, ModeAttribute.NAME)
  if current_mode ~= ModeAttribute.cool.NAME and current_mode ~= ModeAttribute.off.NAME then
    update_device_setpoint(device)
  else
    device.thread:call_with_delay(10, function(d) update_device_setpoint(device) end)
  end
end

local thermostat_mode_handler = function(driver, device, thermostat_mode)
  if THERMOSTAT_SYSTEM_MODE_MAP[thermostat_mode.value] then
    local current_supported_modes = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.supportedThermostatModes.NAME)
    if current_supported_modes then
      device:emit_event(THERMOSTAT_SYSTEM_MODE_MAP[thermostat_mode.value]({data = {supportedThermostatModes = current_supported_modes}}, {visibility = { displayed = false }} ))
    else
      device:emit_event(THERMOSTAT_SYSTEM_MODE_MAP[thermostat_mode.value]())
    end
    update_device_setpoint(device)
  end
end

local function info_changed(driver, device, event, args)
  local modes_index = tonumber(device.preferences.systemModes)
  local new_supported_modes = SUPPORTED_THERMOSTAT_MODES[modes_index]
  device:emit_event(ThermostatMode.supportedThermostatModes(new_supported_modes, { visibility = { displayed = false } }))
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
        [Thermostat.attributes.ThermostatRunningMode.ID] = function() end
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      }
    }
  },
  capability_handlers = {
    [ThermostatCoolingSetpoint.ID] = {
      [ThermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_cooling_setpoint
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    infoChanged = info_changed,
    init = battery_defaults.build_linear_voltage_init(BAT_MIN, BAT_MAX)
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Zen Within" and device:get_model() == "Zen-01"
  end
}

return zenwithin_thermostat
