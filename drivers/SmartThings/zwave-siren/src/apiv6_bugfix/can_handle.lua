-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, cmd, ...)
  local cc = require "st.zwave.CommandClass"
  local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
  local version = require "version"
  if version.api == 6 and
    cmd.cmd_class == cc.WAKE_UP and
    cmd.cmd_id == WakeUp.NOTIFICATION
    then
      return true, require("apiv6_bugfix")
  end
  return false
end

return can_handle
