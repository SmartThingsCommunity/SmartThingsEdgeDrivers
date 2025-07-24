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
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"

local utils = {}

utils.get_preset_level = function(device, component)
  local level = device:get_latest_state(component, "windowShadePreset", "position") or
  device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or
  (device.preferences ~= nil and device.preferences.presetPosition) or
  window_preset_defaults.PRESET_LEVEL

  return level
end

return utils