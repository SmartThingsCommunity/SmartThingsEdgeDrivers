-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })


--- Determine whether the passed device is zwave water temperature humidiry sensor

--- Default handler for notification command class reports
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(self, device, cmd)
  local event
  local water_notification_events_map = {
    [Notification.event.water.LEAK_DETECTED_LOCATION_PROVIDED] = capabilities.waterSensor.water.wet(),
    [Notification.event.water.LEAK_DETECTED] = capabilities.waterSensor.water.wet(),
    [Notification.event.water.STATE_IDLE] = capabilities.waterSensor.water.dry(),
    [Notification.event.water.UNKNOWN_EVENT_STATE] = capabilities.waterSensor.water.dry(),
  }

  if cmd.args.notification_type == Notification.notification_type.WATER then
    event = water_notification_events_map[cmd.args.event]
  end
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = capabilities.tamperAlert.tamper.clear()
    end
  end
  if (event ~= nil) then device:emit_event(event) end
end

local zwave_water_temp_humidity_sensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
  },
  NAME = "zwave water temp humidity sensor",
  can_handle = require("aeotec-water-sensor.can_handle"),
}

return zwave_water_temp_humidity_sensor
