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

local function added_handler(self, device)
  -- Aurora Smart PIR Sensor doesn't report when there is no motion during pairing process
  -- reports are sent only if there is motion detected, so fake event is needed here
  -- device:emit_event(capabilities.motionSensor.motion.inactive())
end

local aurora_motion_driver = {
  NAME = "Aurora Motion Sensor",
  lifecycle_handlers = {
    added = added_handler,
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Aurora" and device:get_model() == "MotionSensor51AU"
  end
}

return aurora_motion_driver
