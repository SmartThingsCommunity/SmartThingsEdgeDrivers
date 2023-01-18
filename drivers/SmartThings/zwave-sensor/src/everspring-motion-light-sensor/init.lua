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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2,strict=true})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})

local EVERSPRING_MOTION_LIGHT_FINGERPRINT = { mfr = 0x0060, prod = 0x0012, model = 0x0001 }

local function can_handle_everspring_motion_light(opts, driver, device, ...)
  return device:id_match(
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.mfr,
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.prod,
    EVERSPRING_MOTION_LIGHT_FINGERPRINT.model
  )
end

local function device_added(driver, device)
  -- device:emit_event(capabilities.motionSensor.motion.inactive())
  device:send(SwitchBinary:Get({}))
  device:send(SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }))
end

local everspring_motion_light = {
  NAME = "Everspring Motion Light",
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_everspring_motion_light
}

return everspring_motion_light
