-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = capabilities.powerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = capabilities.powerSource.powerSource.mains()
    elseif cmd.args.event == Notification.event.power_management.REPLACE_BATTERY_NOW then
      event = capabilities.battery.battery(1)
    elseif cmd.args.event == Notification.event.power_management.BATTERY_IS_FULLY_CHARGED then
      event = capabilities.battery.battery(100)
    end
  elseif cmd.args.notification_type == Notification.notification_type.SYSTEM then
    if cmd.args.event == Notification.event.system.HARDWARE_FAILURE_MANUFACTURER_PROPRIETARY_FAILURE_CODE_PROVIDED then
      if cmd.args.event_parameter:byte(1) == 0 then
        event = capabilities.waterSensor.water.dry()
      elseif cmd.args.event_parameter:byte(1) == 2 then
        event = capabilities.waterSensor.water.wet()
      end
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.battery.battery(100))
  device:emit_event(capabilities.waterSensor.water.dry())
  device:emit_event(capabilities.powerSource.powerSource.mains())
end

local glentronics_water_leak_sensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  NAME = "glentronics water leak sensor",
  can_handle = require("glentronics-water-leak-sensor.can_handle"),
}

return glentronics_water_leak_sensor
