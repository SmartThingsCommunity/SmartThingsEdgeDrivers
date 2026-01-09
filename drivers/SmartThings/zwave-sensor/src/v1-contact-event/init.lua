-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 4 })
local capabilities = require "st.capabilities"


-- This behavior is from zwave-door-window-sensor.groovy, where it is
-- indicated that certain monoprice sensors had this behavior. Also,
-- we have reports of Nortek sensors behaving the same way.
local function handle_v1_contact_event(driver, device, cmd)
  if cmd.args.event == 0x02 or cmd.args.event == 0xFE then
    if cmd.args.v1_alarm_level == 0 then
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.contactSensor.contact.closed())
    else
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.contactSensor.contact.open())
    end
  end
end

local v1_contact_event = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = handle_v1_contact_event
    }
  },
  NAME = "v1 contact event",
  can_handle = require("v1-contact-event.can_handle"),
}

return v1_contact_event
