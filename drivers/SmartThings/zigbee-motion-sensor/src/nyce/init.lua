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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local OccupancySensing = zcl_clusters.OccupancySensing

local ZIGBEE_NYCE_MOTION_SENSOR_FINGERPRINTS = {
  { mfr = "NYCE", model = "3041" },
  { mfr = "NYCE", model = "3043" },
  { mfr = "NYCE", model = "3045" }
}

local is_zigbee_nyce_motion_sensor = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_NYCE_MOTION_SENSOR_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local function occupancy_attr_handler(driver, device, occupancy, zb_rx)
  device:emit_event(
      occupancy.value == 1 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local nyce_motion_handler = {
  NAME = "NYCE Motion Handler",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0)
  },
  zigbee_handlers = {
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      }
    }
  },
  can_handle = is_zigbee_nyce_motion_sensor
}

return nyce_motion_handler
