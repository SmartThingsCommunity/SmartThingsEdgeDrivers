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

local capabilities = require "st.capabilities"
-- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
-- @type st.zwave.CommandClass.Notification
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=4})
-- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
-- @type st.zwave.CommandClass.Association
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
-- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
-- @type st.utils
local utils = require "st.utils"

local WAVE_MOTION_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x0460, prod = 0x0100, productId = 0x0082 }  -- Shelly Wave Motion
}

local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      device:emit_event(capabilities.motionSensor.motion.inactive())
    elseif cmd.args.event == Notification.event.home_security.MOTION_DETECTION then
      event = capabilities.motionSensor.motion.active()
    end
  end

  if event ~= nil then
    device:emit_event(event)
  end
end

local function sensor_multilevel_report_handler(self, device, cmd)
  if cmd.args.sensor_type == SensorMultilevel.sensor_type.LUMINANCE then
    device:emit_event(capabilities.illuminanceMeasurement.illuminance({value = cmd.args.sensor_value, unit = "lux"}))
  end
end

local wave_motion_sensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    },
  },
}
return wave_motion_sensor