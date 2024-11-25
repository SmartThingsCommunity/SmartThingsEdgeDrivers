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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local battery_attribute_configuration = {
  cluster = zcl_clusters.PowerConfiguration.ID,
  attribute = zcl_clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
  minimum_interval = 30,
  maximum_interval = 14300, -- ~4hrs
  data_type = zcl_clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
  reportable_change = 1
}

local function device_init(driver, device)
    device:add_configured_attribute(battery_attribute_configuration)
end

local zigbee_dimmer_remote_driver_template = {
    supported_capabilities = {
        capabilities.battery,
        capabilities.button,
        capabilities.switch,
        capabilities.switchLevel
    },
    lifecycle_handlers = {
      init = device_init,
    },
    sub_drivers = { require("zigbee-accessory-dimmer"), require("zigbee-battery-accessory-dimmer")},
    health_check = false,
}

defaults.register_for_default_handlers(zigbee_dimmer_remote_driver_template, zigbee_dimmer_remote_driver_template.supported_capabilities)
local zigbee_dimmer_remote = ZigbeeDriver("zigbee_dimmer_remote", zigbee_dimmer_remote_driver_template)
zigbee_dimmer_remote:run()
