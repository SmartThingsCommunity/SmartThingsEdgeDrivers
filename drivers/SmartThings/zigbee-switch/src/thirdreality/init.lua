-- Copyright 2023 SmartThings
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

local THIRDREALITY_MOTION_CLUSTER = 0xFC00
local MOTION_SENSOR_VALUE = 0x0002
local MOTION_DETECT = 0x0001
local MOTION_NO_DETECT = 0x0000

local function motion_sensor_attr_handler(driver, device, value, zb_rx)
  if value.value == MOTION_DETECT then
    device:emit_event(capabilities.motionSensor.motion.active())
  elseif value.value == MOTION_NO_DETECT then
    device:emit_event(capabilities.motionSensor.motion.inactive())
  end
end

local thirdreality_device_handler = {
  NAME = "ThirdReality Multi-Function Night Light",
  zigbee_handlers = {
    attr = {
      [THIRDREALITY_MOTION_CLUSTER] = {
        [MOTION_SENSOR_VALUE] = motion_sensor_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Third Reality, Inc" and device:get_model() == "3RSNL02043Z"
  end
}

return thirdreality_device_handler
