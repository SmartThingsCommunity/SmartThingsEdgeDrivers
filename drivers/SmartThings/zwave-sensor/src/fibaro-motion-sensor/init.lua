-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SensorAlarm
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local capabilities = require "st.capabilities"


local function sensor_alarm_report(driver, device, cmd)
  if (cmd.args.sensor_state ~= SensorAlarm.sensor_state.NO_ALARM) then
    device:emit_event(capabilities.accelerationSensor.acceleration.active())
  else
    device:emit_event(capabilities.accelerationSensor.acceleration.inactive())
  end
end

local fibaro_motion_sensor = {
  NAME = "Fibaro Motion Sensor",
  zwave_handlers = {
    [cc.SENSOR_ALARM] = {
      [SensorAlarm.REPORT] = sensor_alarm_report
    }
  },
  can_handle = require("fibaro-motion-sensor.can_handle")
}

return fibaro_motion_sensor
