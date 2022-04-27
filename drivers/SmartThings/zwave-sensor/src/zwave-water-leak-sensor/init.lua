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
local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })


local WATER_LEAK_SENSOR_FINGERPRINTS = {
  {mfr = 0x0084, prod = 0x0063, model = 0x010C},  -- SmartThings Water Leak Sensor
  {mfr = 0x0084, prod = 0x0053, model = 0x0216},  -- FortrezZ Water Leak Sensor
  {mfr = 0x021F, prod = 0x0003, model = 0x0085},  -- Dome Leak Sensor
  {mfr = 0x0258, prod = 0x0003, model = 0x0085},  -- NEO Coolcam Water Sensor
  {mfr = 0x0258, prod = 0x0003, model = 0x1085},  -- NEO Coolcam Water Sensor
  {mfr = 0x0258, prod = 0x0003, model = 0x2085},  -- NEO Coolcam Water Sensor
  {mfr = 0x0086, prod = 0x0002, model = 0x007A},  -- Aeotec Water Sensor 6 (EU)
  {mfr = 0x0086, prod = 0x0102, model = 0x007A},  -- Aeotec Water Sensor 6 (US)
  {mfr = 0x0086, prod = 0x0202, model = 0x007A},  -- Aeotec Water Sensor 6 (AU)
  {mfr = 0x000C, prod = 0x0201, model = 0x000A},  -- HomeSeer LS100+ Water Sensor
  {mfr = 0x0173, prod = 0x4C47, model = 0x4C44},  -- Leak Gopher Z-Wave Leak Detector
  {mfr = 0x027A, prod = 0x7000, model = 0xE002}   -- Zooz ZSE42 XS Water Leak Sensor
}

local function can_handle_water_leak_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(WATER_LEAK_SENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function basic_set_handler(driver, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  device:emit_event(value == 0xFF and capabilities.waterSensor.water.wet() or capabilities.waterSensor.water.dry())
end

local water_leak_sensor = {
  NAME = "Water Leak Sensor",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    }
  },
  can_handle = can_handle_water_leak_sensor
}

return water_leak_sensor
