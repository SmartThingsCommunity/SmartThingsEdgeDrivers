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

local function added_handler(self, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, { visibility = { displayed = false }}))
end

local zigbee_window_treatment_driver_template = {
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.windowShadeLevel,
    capabilities.powerSource,
    capabilities.battery
  },
  sub_drivers = {
    require("vimar"),
    require("aqara"),
    require("feibit"),
    require("somfy"),
    require("invert-lift-percentage"),
    require("rooms-beautiful"),
    require("axis"),
    require("yoolax"),
    require("hanssem"),
    require("screen-innovations")},
  lifecycle_handlers = {
    added = added_handler
  }
}

defaults.register_for_default_handlers(zigbee_window_treatment_driver_template, zigbee_window_treatment_driver_template.supported_capabilities)
local zigbee_window_treatment = ZigbeeDriver("zigbee_window_treatment", zigbee_window_treatment_driver_template)
zigbee_window_treatment:run()
