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

-- ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = zcl_clusters.PowerConfiguration

local capabilities = require "st.capabilities"

local utils = require "st.utils"

-- TODO: the IAS Zone changes should be replaced after supporting functions are included in the lua libs
local do_init = function(driver, device)
  device:remove_monitored_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
  device:remove_configured_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
end

local function samjin_battery_percentage_handler(driver, device, raw_value, zb_rx)
  local raw_percentage = raw_value.value - (200 - raw_value.value) / 2
  local percentage = utils.clamp_value(utils.round(raw_percentage / 2), 0, 100)
  device:emit_event(capabilities.battery.battery(percentage))
end

local samjin_driver = {
  NAME = "Samjin Sensor",
  lifecycle_handlers = {
    init = do_init
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = samjin_battery_percentage_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Samjin"
  end
}

return samjin_driver
