-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=2 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 1 })
local configurationsMap = require "configurations"

local function sensor_alarm_report_handler(driver, device, cmd)
  if (cmd.args.sensor_state == SensorAlarm.sensor_state.ALARM) then
    device:emit_event(capabilities.tamperAlert.tamper.detected())
  elseif (cmd.args.sensor_state == SensorAlarm.sensor_state.NO_ALARM) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local function do_refresh(driver, device)
  device:send(Battery:Get({}))
  device:send(SensorAlarm:Get({}))
  device:send(SensorBinary:Get({}))
end

local function do_configure(driver, device)
  local configuration = configurationsMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, value in ipairs(configuration) do
      device:send(Configuration:Set(value))
    end
  end
  local association = configurationsMap.get_device_association(device)
  if association ~= nil then
    for _, value in ipairs(association) do
      local _node_ids = value.node_ids or {driver.environment_info.hub_zwave_id}
      device:send(Association:Set({grouping_identifier = value.grouping_identifier, node_ids = _node_ids}))
    end
  end

  device:send(Association:Remove({grouping_identifier = 1, node_ids = driver.environment_info.hub_zwave_id}))
end

local function emit_event_if_latest_state_missing(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

local function device_added(driver, device)
  do_refresh(driver, device)
  emit_event_if_latest_state_missing(device, "main", capabilities.contactSensor, capabilities.contactSensor.contact.NAME, capabilities.contactSensor.contact.open())
  emit_event_if_latest_state_missing(device, "main", capabilities.tamperAlert, capabilities.tamperAlert.tamper.NAME, capabilities.tamperAlert.tamper.clear())
end

local fibaro_door_window_sensor_1 = {
  NAME = "fibaro door window sensor 1",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  zwave_handlers = {
    [cc.SENSOR_ALARM ] = {
      [SensorAlarm.REPORT] = sensor_alarm_report_handler
    }
  },
  [capabilities.refresh.ID] = {
    [capabilities.refresh.commands.refresh.NAME] = do_refresh
  },
  can_handle = require("fibaro-door-window-sensor.fibaro-door-window-sensor-1.can_handle"),
}

return fibaro_door_window_sensor_1
