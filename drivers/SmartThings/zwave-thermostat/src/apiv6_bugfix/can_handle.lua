-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, cmd, ...)
  local version = require "version"
  local cc = require "st.zwave.CommandClass"
  local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
  local DANFOSS_LC13_THERMOSTAT_FPS = require "apiv6_bugfix.fingerprints"

  if version.api == 6 and
    cmd.cmd_class == cc.WAKE_UP and
    cmd.cmd_id == WakeUp.NOTIFICATION and not
    (device:id_match(DANFOSS_LC13_THERMOSTAT_FPS[1].manufacturerId,
      DANFOSS_LC13_THERMOSTAT_FPS[1].productType,
      DANFOSS_LC13_THERMOSTAT_FPS[1].productId) or
    device:id_match(DANFOSS_LC13_THERMOSTAT_FPS[2].manufacturerId,
      DANFOSS_LC13_THERMOSTAT_FPS[2].productType,
      DANFOSS_LC13_THERMOSTAT_FPS[2].productId)) then
    return true, require "apiv6_bugfix"
      else
    return false
  end
end

return can_handle
