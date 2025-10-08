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


-- These were added to scripting engine, but this file is to make sure drivers
-- runing on older versions of scripting engine can still access these values
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"

--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })

local defaults = {}

--- WINDOW SHADE PRESET CONSTANTS
defaults.PRESET_LEVEL = 50
defaults.PRESET_LEVEL_KEY = "_presetLevel"

defaults.set_preset_position_cmd = function(driver, device, command)
  device:emit_component_event({id = command.component}, capabilities.windowShadePreset.position(command.args.position))
  device:set_field(defaults.PRESET_LEVEL_KEY, command.args.position, {persist = true})
end

defaults.window_shade_preset_cmd = function(driver, device, command)
  local set
  local get
  local preset_level = device:get_latest_state(command.component, "windowShadePreset", "position") or
    device:get_field(constants.PRESET_LEVEL_KEY) or
    (device.preferences ~= nil and device.preferences.presetPosition) or
    defaults.PRESET_LEVEL
  if device:is_cc_supported(cc.SWITCH_MULTILEVEL) then
    set = SwitchMultilevel:Set({
      value = preset_level,
      duration = constants.DEFAULT_DIMMING_DURATION
    })
    get = SwitchMultilevel:Get({})
  else
    set = Basic:Set({
      value = preset_level
    })
    get = Basic:Get({})
  end
  device:send_to_component(set, command.component)
  local query_device = function()
    device:send_to_component(get, command.component)
  end
  device.thread:call_with_delay(constants.MIN_DIMMING_GET_STATUS_DELAY, query_device)
end

return defaults