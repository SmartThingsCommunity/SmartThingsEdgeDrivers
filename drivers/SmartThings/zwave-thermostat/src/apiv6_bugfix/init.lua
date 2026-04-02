-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cc = require "st.zwave.CommandClass"
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })


local function wakeup_notification(driver, device, cmd)
  device:refresh()
end

local apiv6_bugfix = {
  zwave_handlers = {
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  NAME = "apiv6_bugfix",
  can_handle = require("apiv6_bugfix.can_handle"),
}

return apiv6_bugfix
