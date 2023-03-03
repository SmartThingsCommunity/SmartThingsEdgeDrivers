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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local ZIGBEE_IRIS_MOTION_SENSOR_FINGERPRINTS = {
  { mfr = "iMagic by GreatStar", model = "1117-S" }
}

local is_zigbee_iris_motion_sensor = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_IRIS_MOTION_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local iris_motion_handler = {
  NAME = "Iris Motion Handler",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.4, 2.7)
  },
  can_handle = is_zigbee_iris_motion_sensor
}

return iris_motion_handler
