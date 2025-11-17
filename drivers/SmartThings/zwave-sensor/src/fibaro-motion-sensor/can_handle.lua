-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_motion_sensor(opts, driver, device, ...)
  if device:id_match(FIBARO_MOTION_MFR, FIBARO_MOTION_PROD) then
    local subdriver = require("fibaro-motion-sensor")
    return true, subdriver, require("fibaro-motion-sensor")
  else return false end
end

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
}

return fibaro_motion_sensor
return can_handle_fibaro_motion_sensor
