local cc = require "st.zwave.CommandClass"
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })


local function can_handle(opts, driver, device, cmd, ...)
  local version = require "version"
  return version.api == 6 and
    cmd.cmd_class == cc.WAKE_UP and
    cmd.cmd_id == WakeUp.NOTIFICATION
end

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
  can_handle = can_handle
}

return apiv6_bugfix
