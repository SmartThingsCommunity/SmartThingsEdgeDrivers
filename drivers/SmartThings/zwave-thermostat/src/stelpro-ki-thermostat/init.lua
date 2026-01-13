-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local log = require "log"
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })



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

local function thermostat_mode_report_handler(self, device, cmd)
  local event = nil
  if (cmd.args.mode == ThermostatMode.mode.HEAT) then
    event = capabilities.thermostatMode.thermostatMode.heat()
  elseif (cmd.args.mode == ThermostatMode.mode.ENERGY_SAVE_HEAT) then
    event = capabilities.thermostatMode.thermostatMode.eco()
  else
    log.error("Received an unexpected mode report")
  end

  if (event ~= nil) then
    device:emit_event_for_endpoint(cmd.src_channel, event)
  end
end

local function set_thermostat_mode(driver, device, command)
  local modes = capabilities.thermostatMode.thermostatMode
  local mode = command.args.mode
  local modeValue = nil

  if (mode == modes.heat.NAME) then
    modeValue = ThermostatMode.mode.HEAT
  elseif (mode == modes.eco.NAME) then
    modeValue = ThermostatMode.mode.ENERGY_SAVE_HEAT
  else
    log.error("Received unexpected setThermostatMode command")
  end

  if (modeValue ~= nil) then
    device:send_to_component(ThermostatMode:Set({mode = modeValue}), command.component)

    local follow_up_poll = function()
      device:send_to_component(ThermostatMode:Get({}), command.component)
    end

    device.thread:call_with_delay(1, follow_up_poll)
  end

end

local function device_added(self, device)
  device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())

  -- The DTH for this device supported heat and eco, so we've mirrored that here, despite
  -- the existing, more accurate "energy save heat" mode
  local supported_modes = {}
  table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
  table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.eco.NAME)

  device:emit_event(
    capabilities.thermostatMode.supportedThermostatModes(
      supported_modes,
      { visibility = { displayed = false }}
    )
  )
end

local stelpro_ki_thermostat = {
  NAME = "stelpro ki thermostat",
  zwave_handlers = {
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    },
    [cc.THERMOSTAT_MODE] = {
      [ThermostatMode.REPORT] = thermostat_mode_report_handler,
      [ThermostatMode.SUPPORTED_REPORT] = function(driver, device, cmd) end
    }
  },
  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = require("stelpro-ki-thermostat.can_handle"),
}

return stelpro_ki_thermostat
