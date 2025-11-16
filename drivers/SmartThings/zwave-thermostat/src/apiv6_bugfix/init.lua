local cc = require "st.zwave.CommandClass"
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

local DANFOSS_LC13_THERMOSTAT_FPS = {
    { manufacturerId = 0x0002, productType = 0x0005, productId = 0x0003 }, -- Danfoss LC13 Thermostat
    { manufacturerId = 0x0002, productType = 0x0005, productId = 0x0004 } -- Danfoss LC13 Thermostat
}

local function can_handle(opts, driver, device, cmd, ...)
  local version = require "version"
  return version.api == 6 and
    cmd.cmd_class == cc.WAKE_UP and
    cmd.cmd_id == WakeUp.NOTIFICATION and not
    (device:id_match(DANFOSS_LC13_THERMOSTAT_FPS[1].manufacturerId,
      DANFOSS_LC13_THERMOSTAT_FPS[1].productType,
      DANFOSS_LC13_THERMOSTAT_FPS[1].productId) or
    device:id_match(DANFOSS_LC13_THERMOSTAT_FPS[2].manufacturerId,
      DANFOSS_LC13_THERMOSTAT_FPS[2].productType,
      DANFOSS_LC13_THERMOSTAT_FPS[2].productId))
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
