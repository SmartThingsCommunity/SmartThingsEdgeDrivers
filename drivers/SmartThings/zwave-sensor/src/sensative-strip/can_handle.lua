-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_sensative_strip(opts, driver, device, cmd, ...)
  if device:id_match(SENSATIVE_MFR, nil, SENSATIVE_MODEL) then
    local subdriver = require("sensative-strip")
    return true, subdriver, require("sensative-strip")
  else return false end
end

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
}

return sensative_strip

return can_handle_sensative_strip
