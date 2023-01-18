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

local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local defaults = require "st.zigbee.defaults"
local constants = require "st.zigbee.constants"

--Temperature Measurement
local zigbee_carbon_monoxide_driver_template = {
    supported_capabilities = {
        capabilities.carbonMonoxideDetector,
        capabilities.battery,
    },
    ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
    -- sub_drivers = { require("ClimaxTechnology") }
}

defaults.register_for_default_handlers(zigbee_carbon_monoxide_driver_template, zigbee_carbon_monoxide_driver_template.supported_capabilities)
local zigbee_carbon_monoxide_driver = ZigbeeDriver("zigbee-carbon-monoxide-detector", zigbee_carbon_monoxide_driver_template)
zigbee_carbon_monoxide_driver:run()
