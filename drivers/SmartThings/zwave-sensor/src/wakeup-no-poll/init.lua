-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version = 2})
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

-- Nortek open/closed sensors _always_ respond with "open" when polled, and they are polled after wakeup
local function wakeup_notification(driver, device, cmd)
  --Note sending WakeUpIntervalGet the first time a device wakes up will happen by default in Lua libs 0.49.x and higher
  --This is done to help the hub correctly set the checkInterval for migrated devices.
  if not device:get_field("__wakeup_interval_get_sent") then
    device:send(WakeUp:IntervalGetV1({}))
    device:set_field("__wakeup_interval_get_sent", true)
  end
  if device:get_latest_state("main", capabilities.contactSensor.ID, capabilities.contactSensor.contact.NAME) == nil then
    device:send(SensorBinary:Get({sensor_type = SensorBinary.sensor_type.DOOR_WINDOW}))
  end
  device:send(Battery:Get({}))
end

local wakeup_no_poll = {
  NAME = "wakeup no poll",
  zwave_handlers = {
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  can_handle = require("wakeup-no-poll.can_handle"),
}

return wakeup_no_poll
