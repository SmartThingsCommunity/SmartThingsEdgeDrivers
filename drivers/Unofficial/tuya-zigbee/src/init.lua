-- Copyright 2025 SmartThings
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

local defaults = require "st.zigbee.defaults"
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"

local unofficial_tuya_driver_template = {
  supported_capabilities = {
    capabilities.refresh,
    capabilities.battery
  },
  sub_drivers = {
    require("button"),
    require("curtain"),
    require("motion-sensor"),
    require("smoke-detector"),
    require("switch")
  },
  health_check = false,
}

defaults.register_for_default_handlers(unofficial_tuya_driver_template, unofficial_tuya_driver_template.supported_capabilities)
local unofficial_tuya = ZigbeeDriver("unofficial_tuya", unofficial_tuya_driver_template)
unofficial_tuya:run()