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
local zcl_clusters = require "st.zigbee.zcl.clusters"

local TARGET_DEV_MAJOR = 1
local TARGET_DEV_MINOR = 15
local TARGET_DEV_BUILD = 7

local init_handler = function(self, device)
  -- TODO: the IAS Zone changes should be replaced after supporting functions are included in the lua libs
  device:remove_monitored_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
  device:remove_configured_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)

  local firmware_full_version = device.data.firmwareFullVersion or "0000"
  local dev_major = tonumber(firmware_full_version:sub(1,1), 16)
  local dev_minor = tonumber(firmware_full_version:sub(2,2), 16)
  local dev_build = tonumber(firmware_full_version:sub(3,4), 16)
  local battery_init_function
  -- Centralite Firmware 1.15.7 contains battery smoothing fixes, so versions before that should NOT be smoothed
  if (dev_major < TARGET_DEV_MAJOR) or
     (dev_major == TARGET_DEV_MAJOR and dev_minor < TARGET_DEV_MINOR) or
     (dev_major == TARGET_DEV_MAJOR and dev_minor == TARGET_DEV_MINOR and dev_build < TARGET_DEV_BUILD)
  then
    battery_init_function = battery_defaults.build_linear_voltage_init(2.1, 3.0)
  else
    battery_init_function = battery_defaults.build_linear_voltage_init(2.4, 2.7)
  end
  battery_init_function(self, device)
end

local centralite_handler = {
  NAME = "CentraLite Handler",
  lifecycle_handlers = {
    init = init_handler
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "CentraLite"
  end
}

return centralite_handler
