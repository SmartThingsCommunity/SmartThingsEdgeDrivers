-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({version=2})
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=2})
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({version=1})
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
--- @type st.zwave.CommandClass.ApplicationStatus
local ApplicationStatus = (require "st.zwave.CommandClass.ApplicationStatus")({version=1})

local utils = require "st.utils"


local FORCED_REFRESH_THREAD = "forcedRefreshThread"


local function thermostat_mode_report_handler(self, device, cmd)
  local event = nil
  if (cmd.args.mode == ThermostatMode.mode.OFF) then
    event = capabilities.thermostatMode.thermostatMode.off()
  elseif (cmd.args.mode == ThermostatMode.mode.HEAT) then
    event = capabilities.thermostatMode.thermostatMode.heat()
  elseif (cmd.args.mode == ThermostatMode.mode.MANUFACTURER_SPECIFC) then
    event = capabilities.thermostatMode.thermostatMode.emergency_heat()
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function configuration_report_handler(self, device, cmd)
  if (cmd.args.parameter_number == 3) then
    if cmd.args.configuration_value == 1 then
      if utils.table_size(device.st_store.profile.components) == 1 then
        --- change profile to one with additional component
        device:try_update_metadata({profile = "fibaro-heat-extra-sensor"})
      end
      device:send_to_component(SensorMultilevel:Get({}), "extraTemperatureSensor")
      device:send_to_component(Battery:Get({}), "extraTemperatureSensor")
    elseif (cmd.args.configuration_value == 0 and utils.table_size(device.st_store.profile.components) > 1) then
      device:try_update_metadata({profile = "base-radiator-thermostat"})
    end
  end
end

local function set_thermostat_mode(driver, device, command)
  local modes = capabilities.thermostatMode.thermostatMode
  local mode = command.args.mode
  local modeValue = nil
  if (mode == modes.off.NAME) then
    modeValue = ThermostatMode.mode.OFF
  elseif (mode == modes.heat.NAME) then
    modeValue = ThermostatMode.mode.HEAT
  elseif (mode == modes.emergency_heat.NAME) then
    modeValue = ThermostatMode.mode.MANUFACTURER_SPECIFC
  end

  if (modeValue ~= nil) then
    device:send(ThermostatMode:Set({mode = modeValue}))

    local follow_up_poll = function()
      device:send(ThermostatMode:Get({}))
    end

    device.thread:call_with_delay(1, follow_up_poll)
  end
end

local function application_busy_handler(self, device, cmd)
  local forced_refresh_thread = device:get_field(FORCED_REFRESH_THREAD)
  if forced_refresh_thread then
    device.thread:cancel_timer(forced_refresh_thread)
  end
  forced_refresh_thread = device.thread:call_with_delay(cmd.args.wait_time + 5,
    function()
      device:refresh()
    end
  )
  device:set_field(FORCED_REFRESH_THREAD, forced_refresh_thread)
end

local set_emergency_heat_mode = function()
  return function(driver, device, command)
    set_thermostat_mode(driver, device,{args={mode=capabilities.thermostatMode.thermostatMode.emergency_heat.NAME}})
  end
end

local function do_refresh(self, device)
  device:send(ThermostatMode:Get({}))
  if utils.table_size(device.st_store.profile.components) == 1 then
    device:send(SensorMultilevel:Get({}))
  else
    device:send_to_component(SensorMultilevel:Get({}), "extraTemperatureSensor")
  end
  device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
  device:send(Battery:Get({}))
  device:send(Configuration:Get({parameter_number = 3}))
end

local function endpoint_to_component(device, endpoint)
  if endpoint == 2 then
    return "extraTemperatureSensor"
  else
    return "main"
  end
end

local function component_to_endpoint(device, component)
  if component == "extraTemperatureSensor" then
    return {2}
  else
    return {}
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function device_added(self, device)
  local supported_modes = {
    capabilities.thermostatMode.thermostatMode.off.NAME,
    capabilities.thermostatMode.thermostatMode.heat.NAME,
    capabilities.thermostatMode.thermostatMode.emergency_heat.NAME
  }
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes(supported_modes, { visibility = { displayed = false } }))

  do_refresh(self, device)
end

local fibaro_heat_controller = {
  NAME = "fibaro heat controller",
  zwave_handlers = {
    [cc.THERMOSTAT_MODE] = {
      [ThermostatMode.REPORT] = thermostat_mode_report_handler
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report_handler
    },
    [cc.APPLICATION_STATUS] = {
      [ApplicationStatus.APPLICATION_BUSY] = application_busy_handler
    }
  },
  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [capabilities.thermostatMode.commands.emergencyHeat.NAME] = set_emergency_heat_mode
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = map_components
  },
  can_handle = require("fibaro-heat-controller.can_handle"),
}

return fibaro_heat_controller
