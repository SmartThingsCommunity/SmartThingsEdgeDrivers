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

local zigbee_dimmer_remote_driver_template = {
    supported_capabilities = {
        capabilities.battery,
        capabilities.button,
        capabilities.switch,
        capabilities.switchLevel
    },
    sub_drivers = { require("zigbee-accessory-dimmer"), require("zigbee-battery-accessory-dimmer")}
}

defaults.register_for_default_handlers(zigbee_dimmer_remote_driver_template, zigbee_dimmer_remote_driver_template.supported_capabilities)
local zigbee_dimmer_remote = ZigbeeDriver("zigbee_dimmer_remote", zigbee_dimmer_remote_driver_template)
zigbee_dimmer_remote:run()
