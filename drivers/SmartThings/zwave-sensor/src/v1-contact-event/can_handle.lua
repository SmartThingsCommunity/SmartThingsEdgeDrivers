-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_v1_contact_event(opts, driver, device, cmd, ...)
  local cc = require "st.zwave.CommandClass"
  local Notification = (require "st.zwave.CommandClass.Notification")({ version = 4 })

  if opts.dispatcher_class == "ZwaveDispatcher" and
    cmd ~= nil and
    cmd.cmd_class ~= nil and
    cmd.cmd_class == cc.NOTIFICATION and
    cmd.cmd_id == Notification.REPORT and
    cmd.args.notification_type == Notification.notification_type.HOME_SECURITY and
    cmd.args.v1_alarm_type == 0x07 then
      local subdriver = require("v1-contact-event")
      return true, subdriver
    else
      return false
    end
end

return can_handle_v1_contact_event
