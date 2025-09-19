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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local utils = require "st.utils"
local battery_config = utils.deep_copy(battery_defaults.default_percentage_configuration)
battery_config.reportable_change = 0x10
battery_config.data_type = zcl_clusters.PowerConfiguration.attributes.BatteryVoltage.base_type

local function init_handler(self, device)
  device:add_configured_attribute(battery_config)
end

local samjin_button = {
  NAME = "Samjin Button Handler",
  lifecycle_handlers = {
    init = init_handler
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Samjin" and device:get_model() == "button"
  end
}

return samjin_button
