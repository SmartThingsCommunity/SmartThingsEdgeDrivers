-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })



--- Default handler for notification reports
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(self, device, cmd)
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      device:emit_event(capabilities.switch.switch.off())
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      device:emit_event(capabilities.switch.switch.on())
    end
  end
end

local dawon_smart_plug = {
  NAME = "Dawon smart plug",
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  can_handle = require("dawon-smart-plug.can_handle")
}

return dawon_smart_plug
