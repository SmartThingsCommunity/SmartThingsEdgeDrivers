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
local IASZone = zcl_clusters.IASZone

local ZIGBEE_MOTION_SENSOR_FINGERPRINTS = {
  { mfr = "ORVIBO", model = "895a2d80097f4ae2b2d40500d5e03dcc", timeout = 20 },
  { mfr = "Megaman", model = "PS601/z1", timeout = 20 },
  { mfr = "HEIMAN", model = "PIRSensor-N", timeout = 20 }
}

local is_zigbee_motion_sensor = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_MOTION_SENSOR_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local generate_event_from_zone_status = function(driver, device, zone_status, zigbee_message)
  device:emit_event(
      (zone_status:is_alarm1_set() or zone_status:is_alarm2_set()) and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
  for _, fingerprint in ipairs(ZIGBEE_MOTION_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      device.thread:call_with_delay(fingerprint.timeout, function(d)
          device:emit_event(capabilities.motionSensor.motion.inactive())
        end)
      break
    end
  end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local motion_timeout_handler = {
  NAME = "Motion Timeout Handler",
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    }
  },
  can_handle = is_zigbee_motion_sensor
}

return motion_timeout_handler
