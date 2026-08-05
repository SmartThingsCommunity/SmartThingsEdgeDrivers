-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({version=1})
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({version=1})
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=2})
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})

local LATEST_WAKEUP = "latest_wakeup"
local CACHED_SETPOINT = "cached_setpoint"
local POPP_WAKEUP_INTERVAL = 600 --seconds

local function get_latest_wakeup_timestamp(device)
  return device:get_field(LATEST_WAKEUP)
end

local function set_latest_wakeup_timestamp(device)
  device:set_field(LATEST_WAKEUP, os.time())
end

local function seconds_since_latest_wakeup(device)
  local latest_wakeup = get_latest_wakeup_timestamp(device)
  if latest_wakeup ~= nil then
    return os.difftime(os.time(), latest_wakeup)
  else
    return 0
  end
end

-- POPP is a sleepy device, therefore it won't accept setpoint commands rightaway.
-- That's why driver waits for a device to wake up and then sends cached setpoint command.
-- Driver assumes that wakeUps come in reguraly every 10 minutes.
-- If device wakes up earlier, driver is convinenced that user performed manual action (like adjusting setpoint on device),
-- and in that case, cached setpoint command is removed and not sent.
local function wakeup_notification_handler(self, device, cmd)
  local version = require "version"
  if version.api < 6 then device:send(WakeUp:IntervalGet({})) end
  local setpoint = device:get_field(CACHED_SETPOINT)
  if setpoint ~= nil and seconds_since_latest_wakeup(device) > 0.90 * POPP_WAKEUP_INTERVAL then
    device:send(setpoint)
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
  end
  set_latest_wakeup_timestamp(device)
  device:set_field(CACHED_SETPOINT, nil)
end

local function wakeup_interval_report_handler(self, device, cmd)
  if cmd.args.seconds ~= POPP_WAKEUP_INTERVAL then
    device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = POPP_WAKEUP_INTERVAL}))
  end
end

local function set_heating_setpoint(driver, device, command)
  local scale = ThermostatSetpoint.scale.CELSIUS
  local value = command.args.setpoint

  if (value >= 40) then -- assume this is a fahrenheit value
    value = utils.f_to_c(value)
  end
  local set = ThermostatSetpoint:Set({
    setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
    scale = scale,
    value = value
  })
  device:set_field(CACHED_SETPOINT, set)

  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = value, unit = 'C' }))
end

local function added_handler(self, device)
  device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = POPP_WAKEUP_INTERVAL}))
  device:send(SensorMultilevel:Get({}))
  device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
  device:send(Battery:Get({}))
  set_latest_wakeup_timestamp(device)
end

local popp_radiator_thermostat = {
  NAME = "popp radiator thermostat",
  zwave_handlers = {
    [cc.WAKE_UP] = {
        [WakeUp.NOTIFICATION] = wakeup_notification_handler,
        [WakeUp.INTERVAL_REPORT] = wakeup_interval_report_handler
    }
  },
  capability_handlers = {
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    }
  },
  lifecycle_handlers = {
    added = added_handler
  },
  can_handle = require("popp-radiator-thermostat.can_handle"),
}

return popp_radiator_thermostat
