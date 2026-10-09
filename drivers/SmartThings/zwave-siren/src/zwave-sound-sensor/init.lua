-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })


--- Determine whether the passed device is zwave-sound-sensor
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false

--- Default handler for alarm command class reports
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Alarm.Report
local function alarm_report_handler(driver, device, cmd)
  local alarm_type = cmd.args.z_wave_alarm_type
  local alarm_event = cmd.args.z_wave_alarm_event

  if alarm_type == Alarm.z_wave_alarm_type.SMOKE or alarm_type == Alarm.z_wave_alarm_type.CO then
    if alarm_event == Alarm.z_wave_alarm_event.co.CARBON_MONOXIDE_DETECTED_LOCATION_PROVIDED or
       alarm_event == Alarm.z_wave_alarm_event.co.CARBON_MONOXIDE_DETECTED or
       alarm_event == Alarm.z_wave_alarm_event.smoke.DETECTED_LOCATION_PROVIDED or
       alarm_event == Alarm.z_wave_alarm_event.smoke.DETECTED then
      device:emit_event(capabilities.soundSensor.sound.detected())
    else
      device:emit_event(capabilities.soundSensor.sound.not_detected())
    end
  else
    device:emit_event(capabilities.soundSensor.sound.not_detected())
  end
end

local function added_handler(self, device)
  device:emit_event(capabilities.soundSensor.sound.not_detected())
end

local zwave_sound_sensor = {
  zwave_handlers = {
    [cc.ALARM] = {
      [Alarm.REPORT] = alarm_report_handler
    }
  },
  lifecycle_handlers = {
    added = added_handler,
  },
  NAME = "zwave sound sensor",
  can_handle = require("zwave-sound-sensor.can_handle"),
}

return zwave_sound_sensor
