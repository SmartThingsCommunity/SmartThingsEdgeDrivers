-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
--- @type st.zwave.CommandClass.Battery
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})


--- Determine whether the passed device is multifunctional siren
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false

--- Default handler for notification command class reports
---
--- This converts tamper reports across tamper alert types into tamper events.
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_handler(self, device, cmd)
  local event
  if (cmd.args.notification_type == Notification.notification_type.HOME_SECURITY) then
    if cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      event = capabilities.tamperAlert.tamper.detected()
    else
      event = capabilities.tamperAlert.tamper.clear()
    end
  end
  device:emit_event(event)
end

local do_configure = function(self, device)
  device:refresh()
  device:send(Notification:Get({notification_type = Notification.notification_type.HOME_SECURITY}))
  device:send(Basic:Get({}))
end

local multifunctional_siren = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "multifunctional siren",
  can_handle = require("multifunctional-siren.can_handle"),
}

return multifunctional_siren
