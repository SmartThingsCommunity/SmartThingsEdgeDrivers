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
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4})

local SPRINGS_WINDOW_FINGERPRINTS = {
  {mfr = 0x026E, prod = 0x4353, model = 0x5A31}, -- Springs Window Shade
  {mfr = 0x026E, prod = 0x5253, model = 0x5A31}, -- Springs Roller Shade
}

--- Determine whether the passed device is springs window fashion shade
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is springs window fashion shade, else false
local function can_handle_springs_window_fashion_shade(opts, driver, device, ...)
  for _, fingerprint in ipairs(SPRINGS_WINDOW_FINGERPRINTS) do
    if device:id_match( fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function init_handler(self, device)
  -- This device has a preset position set in hardware, so we need to override the base driver
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.supportedCommands.NAME) == nil then

    -- setPresetPosition is not supported
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition"}, { visibility = { displayed = false }}))
  end
end

local capability_handlers = {}

--- Issue a window shade preset position command to the specified device.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command table ST level capability command
function capability_handlers.preset_position(driver, device)
  local set = SwitchMultilevel:Set({
    value = SwitchMultilevel.value.ON_ENABLE,
    duration = constants.DEFAULT_DIMMING_DURATION
  })
  local get = SwitchMultilevel:Get({})
  device:send(set)
  local query_device = function()
    device:send(get)
  end
  device.thread:call_with_delay(constants.MIN_DIMMING_GET_STATUS_DELAY, query_device)
end

local springs_window_fashion_shade = {
  lifecycle_handlers = {
    init = init_handler
  },
  capability_handlers = {
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = capability_handlers.preset_position
    }
  },
  NAME = "Springs window fashion shade",
  can_handle = can_handle_springs_window_fashion_shade,
}

return springs_window_fashion_shade
