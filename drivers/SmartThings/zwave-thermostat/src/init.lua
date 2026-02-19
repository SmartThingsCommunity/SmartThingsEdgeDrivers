-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.ThermostatFanMode
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({version=3})
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({version=2})
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({version=1})
local ThermostatSetpointV3 = (require "st.zwave.CommandClass.ThermostatSetpoint")({version=3})
local constants = require "st.zwave.constants"
local utils = require "st.utils"

local function device_added(driver, device)
  if device:supports_capability_by_id(capabilities.thermostatMode.ID) and
    device:is_cc_supported(cc.THERMOSTAT_MODE) then
    device:send(ThermostatMode:SupportedGet({}))
  end
  if device:supports_capability_by_id(capabilities.thermostatFanMode.ID) and
    device:is_cc_supported(cc.THERMOSTAT_FAN_MODE) then
    device:send(ThermostatFanMode:SupportedGet({}))
  end
  if device:is_cc_supported(cc.THERMOSTAT_SETPOINT) then
    if device:supports_capability_by_id(capabilities.thermostatCoolingSetpoint.ID) then
      device:send(ThermostatSetpointV3:CapabilitiesGet({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
    end
    if device:supports_capability_by_id(capabilities.thermostatHeatingSetpoint.ID) then
      device:send(ThermostatSetpointV3:CapabilitiesGet({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
    end
  end
  device:refresh()
end

--TODO: Update this once we've decided how to handle setpoint commands
local function convert_to_device_temp(command_temp, device_scale)
  -- under 40, assume celsius
  if (command_temp < 40 and device_scale == ThermostatSetpoint.scale.FAHRENHEIT) then
    command_temp = utils.c_to_f(command_temp)
  elseif (command_temp >= 40 and (device_scale == ThermostatSetpoint.scale.CELSIUS or device_scale == nil)) then
    command_temp = utils.f_to_c(command_temp)
  end
  return command_temp
end

local function set_setpoint_factory(setpoint_type)
  return function(driver, device, command)
    local scale = device:get_field(constants.TEMPERATURE_SCALE)
    local value = convert_to_device_temp(command.args.setpoint, scale)

    -- Zwave thermostat devices expect to get fractional values as an integer value
    -- with a provided precision such that the temp is value * 10^(-precision)
    -- See section 2.2.113.2 of the Zwave Specification for more info
    -- This is a temporary workaround for the Aeotec Thermostat device while
    -- more permanent fixes are added to scripting-engine
    local set
    if value % 1 == 0.5 then
      set = ThermostatSetpoint:Set({
        setpoint_type = setpoint_type,
        scale = scale,
        value = value,
        precision = 1,
        size = 2
      })
    else
      -- There have been issues with some thermostats failing to handle non-integer values
      -- correctly. This rounding is intended to be removed.
      value = utils.round(value)
      set = ThermostatSetpoint:Set({
        setpoint_type = setpoint_type,
        scale = scale,
        value = value
      })
    end
    device:send_to_component(set, command.component)

    local follow_up_poll = function()
      device:send_to_component(ThermostatSetpoint:Get({setpoint_type = setpoint_type}), command.component)
    end

    device.thread:call_with_delay(1, follow_up_poll)
  end
end

local function setpoint_capabilites_report(driver, device, cmd)
  local args = cmd.args
  local min_temp = args.min_value
  local max_temp = args.max_value

  local scale = 'C'
  if args.scale1 == ThermostatSetpoint.scale.FAHRENHEIT then
    scale = 'F'
  end

  local capability_constructor = nil
  if args.setpoint_type == ThermostatSetpoint.setpoint_type.HEATING_1 then
    capability_constructor = capabilities.thermostatHeatingSetpoint.heatingSetpointRange
  elseif args.setpoint_type == ThermostatSetpoint.setpoint_type.COOLING_1 then
    capability_constructor = capabilities.thermostatCoolingSetpoint.coolingSetpointRange
  end

  if capability_constructor then
    device:emit_event_for_endpoint(cmd.src_channel, capability_constructor(
      {
        unit = scale,
        value = {minimum = min_temp, maximum = max_temp}
      }
    ))
  end
end

local driver_template = {
  supported_capabilities = {
    capabilities.temperatureAlarm,
    capabilities.temperatureMeasurement,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatOperatingState,
    capabilities.thermostatMode,
    capabilities.thermostatFanMode,
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
    capabilities.powerMeter,
    capabilities.energyMeter
  },
  capability_handlers = {
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint_factory(ThermostatSetpoint.setpoint_type.COOLING_1)
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint_factory(ThermostatSetpoint.setpoint_type.HEATING_1)
    }
  },
  zwave_handlers = {
    [cc.THERMOSTAT_SETPOINT] = {
      [ThermostatSetpoint.CAPABILITIES_REPORT] = setpoint_capabilites_report
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  sub_drivers = require("sub_drivers"),
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities, {native_capability_attrs_enabled = true})
--- @type st.zwave.Driver
local thermostat = ZwaveDriver("zwave_thermostat", driver_template)
thermostat:run()
