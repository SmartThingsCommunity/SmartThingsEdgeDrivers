-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_tamper_event(opts, driver, device, cmd, ...)
  local cc = require "st.zwave.CommandClass"
  local Notification = (require "st.zwave.CommandClass.Notification")({ version = 4 })
  local FIBARO_DOOR_WINDOW_MFR_ID = 0x010F

  if device.zwave_manufacturer_id ~= FIBARO_DOOR_WINDOW_MFR_ID and
    opts.dispatcher_class == "ZwaveDispatcher" and
    cmd ~= nil and
    cmd.cmd_class ~= nil and
    cmd.cmd_class == cc.NOTIFICATION and
    cmd.cmd_id == Notification.REPORT and
    cmd.args.notification_type == Notification.notification_type.HOME_SECURITY and
    (cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED or
    cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_MOVED) then
      return true, require("timed-tamper-clear")
    end
    return false
end

return can_handle_tamper_event
