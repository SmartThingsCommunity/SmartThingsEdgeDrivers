-- Copyright 2021 SmartThings
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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

local ZWAVE_MOTION_TEMP_LIGHT_SENSOR_FINGERPRINTS = {
  {mfr = 0x0371, prod = 0x0002, model = 0x0005}, -- ZW005-C EU Aeotec TriSensor
  {mfr = 0x0371, prod = 0x0102, model = 0x0005}, -- ZW005-A US Aeotec TriSensor
  {mfr = 0x0371, prod = 0x0202, model = 0x0005}  -- ZW005-B AU Aeotec TriSensor
}

local function can_handle_zwave_motion_temp_light_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_MOTION_TEMP_LIGHT_SENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function do_configure(self, device)
    -- This configures the clear time when your sensor times out and sends a no motion status
    -------------------------------------------------
    -- Parameter # : 2
    -- Size : 2
    -- Value : 1~32767
    -- Descrition : Clear/timeout time in seconds.
    -- DEFAULT SETTING : 240
    -------------------------------------------------
    device:send(Configuration:Set({parameter_number=2, size=2, configuration_value=30}))
end

local zwave_motion_temp_light_sensor = {
    lifecycle_handlers = {
      doConfigure = do_configure
    },
    NAME = "zwave motion temp light sensor",
    can_handle = can_handle_zwave_motion_temp_light_sensor,
}

return zwave_motion_temp_light_sensor
