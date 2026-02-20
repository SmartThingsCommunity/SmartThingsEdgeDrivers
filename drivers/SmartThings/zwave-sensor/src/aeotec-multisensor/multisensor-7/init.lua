-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })

local PREFERENCE_NUM = 10

local function wakeup_notification(driver, device, cmd)
  --Note sending WakeUpIntervalGet the first time a device wakes up will happen by default in Lua libs 0.49.x and higher
  --This is done to help the hub correctly set the checkInterval for migrated devices.
  if not device:get_field("__wakeup_interval_get_sent") then
    device:send(WakeUp:IntervalGetV1({}))
    device:set_field("__wakeup_interval_get_sent", true)
  end
  device:send(Configuration:Get({parameter_number = PREFERENCE_NUM}))
  device:refresh()
end

local function configuration_report_handler(self, device, cmd)
  local power_source
  if cmd.args.parameter_number == PREFERENCE_NUM then
    if cmd.args.configuration_value == 0 then
        power_source = capabilities.powerSource.powerSource.battery()
      else
        power_source = capabilities.powerSource.powerSource.dc()
      end
  end

  if power_source ~= nil then
    device:emit_event(power_source)
  end
end

local multisensor_7 = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report_handler
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  NAME = "aeotec multisensor 7",
  can_handle = require("aeotec-multisensor.multisensor-7.can_handle"),
}

return multisensor_7
