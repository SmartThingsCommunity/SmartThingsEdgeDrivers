-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

local LEAKAGE_ALARM_PARAM = 12
local LEAKAGE_ALARM_OFF = 0
local SENSATIVE_COMFORT_PROFILE = "illuminance-temperature"
local CONFIG_REPORT_RECEIVED = "configReportReceived"

local function configuration_report(driver, device, cmd)
  local parameter_number = cmd.args.parameter_number
  local configuration_value = cmd.args.configuration_value

  if parameter_number == LEAKAGE_ALARM_PARAM then
    device:set_field(CONFIG_REPORT_RECEIVED, true, {persist = true})
    if configuration_value == LEAKAGE_ALARM_OFF then
      device:try_update_metadata({profile = SENSATIVE_COMFORT_PROFILE})
    end
  end
end

local function do_configure(driver, device)
  device:refresh()
  device:send(Configuration:Get({ parameter_number = LEAKAGE_ALARM_PARAM }))
end

local function wakeup_notification(driver, device, cmd)
  --Note sending WakeUpIntervalGet the first time a device wakes up will happen by default in Lua libs 0.49.x and higher
  --This is done to help the hub correctly set the checkInterval for migrated devices.
  if not device:get_field("__wakeup_interval_get_sent") then
    device:send(WakeUp:IntervalGetV1({}))
    device:set_field("__wakeup_interval_get_sent", true)
  end
  if device:get_field(CONFIG_REPORT_RECEIVED) ~= true then
    device:send(Configuration:Get({ parameter_number = LEAKAGE_ALARM_PARAM }))
  end
end

local sensative_strip = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "sensative_strip",
  can_handle = require("sensative-strip.can_handle")
}

return sensative_strip
