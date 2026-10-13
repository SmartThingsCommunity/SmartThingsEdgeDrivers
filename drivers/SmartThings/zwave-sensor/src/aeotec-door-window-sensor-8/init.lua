-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 11 })

local MoldHealthConcern = capabilities.moldHealthConcern
local ContactSensor = capabilities.contactSensor
local PowerSource = capabilities.powerSource
local ThreeAxis = capabilities.threeAxis
local TamperAlert = capabilities.tamperAlert

local function added_handler(driver, device)
  device:emit_event(MoldHealthConcern.supportedMoldValues({"good", "unhealthy"}))

  -- Default value
  device:emit_event(MoldHealthConcern.moldHealthConcern.good())

  -- Default value
  device:emit_event(PowerSource.powerSource.battery())

  device:send(Battery:Get({}))
end

local function notification_report_handler(self, device, cmd)
  local event

  -- DOOR_WINDOW
  if cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL then
    if cmd.args.event == Notification.event.access_control.WINDOW_DOOR_IS_CLOSED then
      event = ContactSensor.contact.closed()
    elseif cmd.args.event == Notification.event.access_control.WINDOW_DOOR_IS_OPEN then
      event = ContactSensor.contact.open()
    end
  end

  -- POWER
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = PowerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = PowerSource.powerSource.dc()
    elseif cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED then
      device:send(Battery:Get({}))
    end
  end

  -- MOLD
  if cmd.args.notification_type == Notification.notification_type.WEATHER_ALARM then
    if cmd.args.event == Notification.event.weather_alarm.STATE_IDLE then
      event = MoldHealthConcern.moldHealthConcern.good()
    elseif cmd.args.event == Notification.event.weather_alarm.MOISTURE_ALARM then
      event = MoldHealthConcern.moldHealthConcern.unhealthy()
    end
  end

  -- TAMPER
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = TamperAlert.tamper.clear()
    elseif cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      event = TamperAlert.tamper.detected()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local aeotec_door_window_sensor_8 = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
  },
  lifecycle_handlers = {
    added = added_handler
  },
  NAME = "Aeotec Door Window Sensor  8",
  can_handle = require("aeotec-door-window-sensor-8.can_handle"),
}

return aeotec_door_window_sensor_8
