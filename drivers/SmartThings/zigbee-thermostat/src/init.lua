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

-- Zigbee Driver utilities
local ZigbeeDriver      = require "st.zigbee"
local device_management = require "st.zigbee.device_management"
local defaults          = require "st.zigbee.defaults"
local utils             = require "st.utils"

-- Zigbee Spec Utils
local clusters                      = require "st.zigbee.zcl.clusters"
local PowerConfiguration            = clusters.PowerConfiguration
local Thermostat                    = clusters.Thermostat
local FanControl                    = clusters.FanControl

local FanMode = FanControl.attributes.FanMode
local FanModeSequence           = FanControl.attributes.FanModeSequence
local ThermostatSystemMode      = Thermostat.attributes.SystemMode
local ThermostatControlSequence = Thermostat.attributes.ControlSequenceOfOperation

-- Capabilities
local capabilities              = require "st.capabilities"
local TemperatureMeasurement    = capabilities.temperatureMeasurement
local ThermostatCoolingSetpoint = capabilities.thermostatCoolingSetpoint
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode            = capabilities.thermostatMode
local ThermostatFanMode         = capabilities.thermostatFanMode
local ThermostatOperatingState  = capabilities.thermostatOperatingState
local Battery                   = capabilities.battery
local PowerSource               = capabilities.powerSource
local RelativeHumidity          = capabilities.relativeHumidityMeasurement

-- lux thermostat uses min 5V, max of 6.5V
local BAT_MIN = 50.0
local BAT_MAX = 65.0

local THERMOSTAT_MODE_MAP = {
  [ThermostatSystemMode.OFF]               = ThermostatMode.thermostatMode.off,
  [ThermostatSystemMode.AUTO]              = ThermostatMode.thermostatMode.auto,
  [ThermostatSystemMode.COOL]              = ThermostatMode.thermostatMode.cool,
  [ThermostatSystemMode.HEAT]              = ThermostatMode.thermostatMode.heat,
  [ThermostatSystemMode.EMERGENCY_HEATING] = ThermostatMode.thermostatMode.emergency_heat
}

local FAN_MODE_MAP = {
  [FanMode.ON]   = ThermostatFanMode.thermostatFanMode.on,
  [FanMode.AUTO] = ThermostatFanMode.thermostatFanMode.auto
}

-- Some Zigbee fan modes do not have analogous values in the ThermostatFanMode capability, so they are left as raw strings
local SUPPORTED_FAN_MODES = {
  [FanModeSequence.LOW_MED_HIGH]      = { "FAN_MODE_LOW", "FAN_MODE_MEDIUM", "FAN_MODE_HIGH"},
  [FanModeSequence.LOW_HIGH]          = { "FAN_MODE_LOW", "FAN_MODE_HIGH"},
  [FanModeSequence.LOW_MED_HIGH_AUTO] = { "FAN_MODE_LOW", "FAN_MODE_MEDIUM", "FAN_MODE_HIGH", ThermostatFanMode.thermostatFanMode.auto.NAME},
  [FanModeSequence.LOW_HIGH_AUTO]     = { "FAN_MODE_LOW", "FAN_MODE_HIGH", ThermostatFanMode.thermostatFanMode.auto.NAME},
  [FanModeSequence.ON_AUTO]           = { ThermostatFanMode.thermostatFanMode.on.NAME, ThermostatFanMode.thermostatFanMode.auto.NAME}, -- Should only be this one
}

-- Map the Zigbee attribute value to the corresponding capability for supported modes
local SUPPORTED_THERMOSTAT_MODES = {
  [ThermostatControlSequence.COOLING_ONLY]                    = { ThermostatMode.thermostatMode.off.NAME,
                                                                  ThermostatMode.thermostatMode.cool.NAME},
  [ThermostatControlSequence.COOLING_WITH_REHEAT]             = { ThermostatMode.thermostatMode.off.NAME,
                                                                  ThermostatMode.thermostatMode.cool.NAME},
  [ThermostatControlSequence.HEATING_ONLY]                    = { ThermostatMode.thermostatMode.off.NAME,
                                                                  ThermostatMode.thermostatMode.heat.NAME,
                                                                  ThermostatMode.thermostatMode.emergency_heat.NAME},
  [ThermostatControlSequence.HEATING_WITH_REHEAT]             = { ThermostatMode.thermostatMode.off.NAME,
                                                                  ThermostatMode.thermostatMode.heat.NAME,
                                                                  ThermostatMode.thermostatMode.emergency_heat.NAME},
  [ThermostatControlSequence.COOLING_AND_HEATING4PIPES]             = { ThermostatMode.thermostatMode.off.NAME,
                                                                        ThermostatMode.thermostatMode.heat.NAME,
                                                                        ThermostatMode.thermostatMode.auto.NAME,
                                                                        ThermostatMode.thermostatMode.cool.NAME,
                                                                        ThermostatMode.thermostatMode.emergency_heat.NAME},
  [ThermostatControlSequence.COOLING_AND_HEATING4PIPES_WITH_REHEAT] = { ThermostatMode.thermostatMode.off.NAME,
                                                                        ThermostatMode.thermostatMode.heat.NAME,
                                                                        ThermostatMode.thermostatMode.auto.NAME,
                                                                        ThermostatMode.thermostatMode.cool.NAME,
                                                                        ThermostatMode.thermostatMode.emergency_heat.NAME}
}

local battery_voltage_handler = function(driver, device, battery_voltage)
  if (battery_voltage.value == 0) then -- this means we're plugged in
    device:emit_event(PowerSource.powerSource.mains())
    device:emit_event(Battery.battery(100))
  else
    local perc_value = utils.round((battery_voltage.value - BAT_MIN)/(BAT_MAX - BAT_MIN) * 100)
    device:emit_event(Battery.battery(utils.clamp_value(perc_value, 0, 100)))
  end
end

local power_source_handler = function(driver, device, battery_alarm_mask)
  if (battery_alarm_mask:is_bit_set(31)) then
    device:emit_event(PowerSource.powerSource.battery())
  else
    device:emit_event(PowerSource.powerSource.mains())
  end
end

local supported_thermostat_modes_handler = function(driver, device, supported_modes)
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_THERMOSTAT_MODES[supported_modes.value], { visibility = { displayed = false } }))
end

local thermostat_mode_handler = function(driver, device, thermostat_mode)
  if THERMOSTAT_MODE_MAP[thermostat_mode.value] then
    device:emit_event(THERMOSTAT_MODE_MAP[thermostat_mode.value]())
  end
end

local thermostat_operating_state_handler = function(driver, device, operating_state)
  if (operating_state:is_heat_second_stage_on_set() or operating_state:is_heat_on_set()) then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.heating())
  elseif (operating_state:is_cool_second_stage_on_set() or operating_state:is_cool_on_set()) then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.cooling())
  elseif (operating_state:is_fan_on_set()) then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.fan_only())
  else
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.idle())
  end
end

local supported_fan_modes_handler = function(driver, device, fan_mode)
  device:emit_event(ThermostatFanMode.supportedThermostatFanModes(SUPPORTED_FAN_MODES[fan_mode.value], { visibility = { displayed = false }}))
end

local thermostat_fan_mode_handler = function(driver, device, attr_fan_mode)
  if (FAN_MODE_MAP[attr_fan_mode.value]) then
    local supported_fan_modes = device:get_latest_state("main", ThermostatFanMode.ID, ThermostatFanMode.supportedThermostatFanModes.NAME)
    if supported_fan_modes then
      device:emit_event(FAN_MODE_MAP[attr_fan_mode.value]({data = {supportedThermostatFanModes = supported_fan_modes}}))
    else
      device:emit_event(FAN_MODE_MAP[attr_fan_mode.value]())
    end
  end
end

local set_thermostat_mode = function(driver, device, command)
  for zigbee_attr_val, st_cap_val in pairs(THERMOSTAT_MODE_MAP) do
    if command.args.mode == st_cap_val.NAME then
      device:send_to_component(command.component, Thermostat.attributes.SystemMode:write(device, zigbee_attr_val))
      device.thread:call_with_delay(1, function(d)
        device:send_to_component(command.component, Thermostat.attributes.SystemMode:read(device))
      end)
      break
    end
  end
end

local thermostat_mode_setter = function(mode_name)
  return function(driver, device, command)
    return set_thermostat_mode(driver, device, {component = command.component, args = {mode = mode_name}})
  end
end

local set_thermostat_fan_mode = function(driver, device, command)
  for zigbee_attr_val, st_cap_val in pairs(FAN_MODE_MAP) do
    if command.args.mode == st_cap_val.NAME then
      device:send_to_component(command.component, FanControl.attributes.FanMode:write(device, zigbee_attr_val))
      device.thread:call_with_delay(1, function(d)
        device:send_to_component(command.component, FanControl.attributes.FanMode:read(device))
      end)
      break
    end
  end
end

local thermostat_fan_mode_setter = function(mode_name)
  return function(driver, device, command)
		return set_thermostat_fan_mode(driver, device, {component = command.component, args = {mode = mode_name}})
	end
end

--TODO: Update this once we've decided how to handle setpoint commands
local set_setpoint_factory = function(setpoint_attribute)
  return function(driver, device, command)
    local value = command.args.setpoint
    if (value >= 40) then -- assume this is a fahrenheit value
      value = utils.f_to_c(value)
    end
    device:send_to_component(command.component, setpoint_attribute:write(device, utils.round(value*100)))

    device.thread:call_with_delay(2, function(d)
      device:send_to_component(command.component, setpoint_attribute:read(device))
    end)
  end
end

local do_refresh = function(self, device)
  local attributes = {
    Thermostat.attributes.OccupiedCoolingSetpoint,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.ControlSequenceOfOperation,
    Thermostat.attributes.ThermostatRunningState,
    Thermostat.attributes.SystemMode,
    FanControl.attributes.FanModeSequence,
    FanControl.attributes.FanMode,
    PowerConfiguration.attributes.BatteryVoltage,
    PowerConfiguration.attributes.BatteryAlarmState
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, FanControl.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
end

local device_added = function(self, device)
  do_refresh(self, device)
end

local zigbee_thermostat_driver = {
  supported_capabilities = {
    TemperatureMeasurement,
    ThermostatCoolingSetpoint,
    ThermostatHeatingSetpoint,
    ThermostatMode,
    ThermostatFanMode,
    ThermostatOperatingState,
    RelativeHumidity,
    Battery,
    PowerSource
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_voltage_handler,
        [PowerConfiguration.attributes.BatteryAlarmState.ID] = power_source_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler,
        [Thermostat.attributes.ThermostatRunningState.ID] = thermostat_operating_state_handler,
        [Thermostat.attributes.ThermostatRunningMode.ID] = thermostat_mode_handler,
        [Thermostat.attributes.SystemMode.ID] = thermostat_mode_handler
      },
      [FanControl.ID] = {
        [FanControl.attributes.FanModeSequence.ID] = supported_fan_modes_handler,
        [FanControl.attributes.FanMode.ID] = thermostat_fan_mode_handler
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
    [ThermostatFanMode.ID] = {
      [ThermostatFanMode.commands.setThermostatFanMode.NAME] = set_thermostat_fan_mode,
      [ThermostatFanMode.commands.fanAuto.NAME] = thermostat_fan_mode_setter(ThermostatFanMode.thermostatFanMode.auto.NAME),
      [ThermostatFanMode.commands.fanOn.NAME] = thermostat_fan_mode_setter(ThermostatFanMode.thermostatFanMode.on.NAME)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint_factory(clusters.Thermostat.attributes.OccupiedCoolingSetpoint)
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint_factory(clusters.Thermostat.attributes.OccupiedHeatingSetpoint)
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = device_added
  },
  sub_drivers = {
    require("zenwithin"),
    require("fidure"),
    require("sinope"),
    require("stelpro-ki-zigbee-thermostat"),
    require("stelpro"),
    require("lux-konoz"),
    require("leviton"),
    require("danfoss"),
    require("popp"),
    require("vimar"),
    require("resideo_korea")
  },
}

defaults.register_for_default_handlers(zigbee_thermostat_driver, zigbee_thermostat_driver.supported_capabilities)
local thermostat = ZigbeeDriver("zigbee-thermostat", zigbee_thermostat_driver)
thermostat:run()
