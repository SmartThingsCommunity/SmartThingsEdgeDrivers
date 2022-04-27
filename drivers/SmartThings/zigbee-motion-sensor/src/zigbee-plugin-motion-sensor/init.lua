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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local OccupancySensing = zcl_clusters.OccupancySensing

local ZIGBEE_PLUGIN_MOTION_SENSOR_FINGERPRINTS = {
  { model = "E280-KR0A0Z0-HA" }
}

local is_zigbee_plugin_motion_sensor = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_PLUGIN_MOTION_SENSOR_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function occupancy_attr_handler(driver, device, occupancy, zb_rx)
  device:emit_event(occupancy.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, OccupancySensing.ID, self.environment_info.hub_zigbee_eui))
end

local do_refresh = function(self, device)
  device:send(OccupancySensing.attributes.Occupancy:read(device))
end

local zigbee_plugin_motion_sensor = {
  NAME = "zigbee plugin motion sensor",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = is_zigbee_plugin_motion_sensor
}

return zigbee_plugin_motion_sensor
