-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })

local function emit_event_if_latest_state_missing(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

local function device_added(self, device)
  emit_event_if_latest_state_missing(device, "main", capabilities.tamperAlert, capabilities.tamperAlert.tamper.NAME, capabilities.tamperAlert.tamper.clear())
  emit_event_if_latest_state_missing(device, "main", capabilities.contactSensor, capabilities.contactSensor.contact.NAME, capabilities.contactSensor.contact.open())
  emit_event_if_latest_state_missing(device, "main", capabilities.temperatureAlarm, capabilities.temperatureAlarm.temperatureAlarm.NAME, capabilities.temperatureAlarm.temperatureAlarm.cleared())
end

local function alarm_report_handler(self, device, cmd)
  local zwave_alarm_type = cmd.args.z_wave_alarm_type
  local zwave_alarm_event = cmd.args.z_wave_alarm_event
  local event
  if zwave_alarm_type == Alarm.z_wave_alarm_type.ACCESS_CONTROL then
    if zwave_alarm_event == 22 then
      event = capabilities.contactSensor.contact.open()
    elseif zwave_alarm_event == 23 then
      event = capabilities.contactSensor.contact.closed()
    end
  elseif zwave_alarm_type == Alarm.z_wave_alarm_type.BURGLAR then
    if zwave_alarm_event == 0 then
      event = capabilities.tamperAlert.tamper.clear()
    elseif zwave_alarm_event == Alarm.z_wave_alarm_event.burglar.TAMPERING_PRODUCT_COVER_REMOVED then
      event = capabilities.tamperAlert.tamper.detected()
    end
  elseif zwave_alarm_type == Alarm.z_wave_alarm_type.HEAT then
    if zwave_alarm_event == 0 then
      event = capabilities.temperatureAlarm.temperatureAlarm.cleared()
    elseif zwave_alarm_event == Alarm.z_wave_alarm_event.heat.OVERDETECTED then
      event = capabilities.temperatureAlarm.temperatureAlarm.heat()
    elseif zwave_alarm_event == Alarm.z_wave_alarm_event.heat.UNDER_DETECTED then
      event = capabilities.temperatureAlarm.temperatureAlarm.freeze()
    end
  end
  if event ~= nil then device:emit_event(event) end
end

local fibaro_door_window_sensor_2 = {
  NAME = "fibaro door window sensor 2",
  zwave_handlers = {
    [cc.ALARM] = {
      [Alarm.REPORT] = alarm_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = require("fibaro-door-window-sensor.fibaro-door-window-sensor-2.can_handle"),
}

return fibaro_door_window_sensor_2
