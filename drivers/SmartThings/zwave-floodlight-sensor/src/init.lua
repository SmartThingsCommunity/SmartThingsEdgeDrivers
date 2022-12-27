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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})

local HOMESEER_FLS100PLUS_FINGERPRINT = { mfr = 0x000C, prod = 0x0201, model = 0x000B }

local function can_handle_homeseer_fls100plus(opts, driver, device, ...)
  return device:id_match(
    HOMESEER_FLS100PLUS_FINGERPRINT.mfr,
    HOMESEER_FLS100PLUS_FINGERPRINT.prod,
    HOMESEER_FLS100PLUS_FINGERPRINT.model
  )
end

local function device_added(driver, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:send(SwitchBinary:Get({}))
  device:send(SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }))
end

local homeseer_fls100plus = {
  NAME = "HomeSeer FLS100+ Floodlight Sensor",
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_homeseer_fls100plus
}

return homeseer_fls100plus
