-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SensorAlarm
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local capabilities = require "st.capabilities"

local FIBARO_MOTION_MFR = 0x010F
local FIBARO_MOTION_PROD = 0x0800

local function can_handle_fibaro_motion_sensor(opts, driver, device, ...)
  return device:id_match(FIBARO_MOTION_MFR, FIBARO_MOTION_PROD)
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
  can_handle = can_handle_fibaro_motion_sensor
}

return fibaro_motion_sensor