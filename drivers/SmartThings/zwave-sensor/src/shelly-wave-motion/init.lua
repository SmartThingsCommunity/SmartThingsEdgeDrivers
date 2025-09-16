-- Copyright 2025 SmartThings
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