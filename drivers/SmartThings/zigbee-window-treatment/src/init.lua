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
local window_shade_utils = require "window_shade_utils"

local function init_handler(self, device)
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
      device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME) == nil then

    -- These should only ever be nil once (and at the same time) for already-installed devices
    -- It can be relocated to `added` after migration is complete
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, { visibility = { displayed = false }}))

    local preset_position = device:get_field(window_shade_utils.PRESET_LEVEL_KEY) or
      (device.preferences ~= nil and device.preferences.presetPosition) or
      window_shade_utils.PRESET_LEVEL

    device:emit_event(capabilities.windowShadePreset.position(preset_position, { visibility = {displayed = false}}))
    device:set_field(window_shade_utils.PRESET_LEVEL_KEY, preset_position, {persist = true})
  end
end

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
    require("screen-innovations"),
	require("VIVIDSTORM")},
  lifecycle_handlers = {
    init = init_handler,
    added = added_handler
  },
  capability_handlers = {
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.setPresetPosition.NAME] = window_shade_utils.set_preset_position_cmd,
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_utils.window_shade_preset_cmd,
    }
  },
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_window_treatment_driver_template, zigbee_window_treatment_driver_template.supported_capabilities)
local zigbee_window_treatment = ZigbeeDriver("zigbee_window_treatment", zigbee_window_treatment_driver_template)
zigbee_window_treatment:run()
