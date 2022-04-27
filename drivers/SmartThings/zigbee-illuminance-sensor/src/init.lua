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
local device_management = require "st.zigbee.device_management"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"
local IlluminanceMeasurement = clusters.IlluminanceMeasurement


local zigbee_illuminance_driver = {
  supported_capabilities = {
    capabilities.illuminanceMeasurement,
    capabilities.battery
  },
}

defaults.register_for_default_handlers(zigbee_illuminance_driver, zigbee_illuminance_driver.supported_capabilities)
local driver = ZigbeeDriver("zigbee-illuminance-sensor", zigbee_illuminance_driver)
driver:run()
