-- Copyright 2021 SmartThings
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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"
local window_shade_defaults = require "st.zigbee.defaults.windowShade_defaults"
local WindowCovering = zcl_clusters.WindowCovering

local GLYDEA_MOVE_THRESHOLD = 3

local ZIGBEE_WINDOW_SHADE_FINGERPRINTS = {
    { mfr = "SOMFY", model = "Glydea Ultra Curtain" },
    { mfr = "SOMFY", model = "Roller" },
}

local SAME_LEVEL_EVENT = "_sameLevelEvent"

local is_zigbee_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_WINDOW_SHADE_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  -- Somfy Device report as invert value
  local level = 100 - value.value
  local current_level = device:get_latest_state(device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
    capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  local windowShade = capabilities.windowShade.windowShade
  local is_same_level_set = device:get_field(SAME_LEVEL_EVENT) or false
  -- Need to emit event if Level are same when setLevel cmd is given
  if current_level ~= level or current_level == nil or is_same_level_set then
    device:set_field(SAME_LEVEL_EVENT, false)
    current_level = current_level or 0
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
    local event = nil
    if level == 0 or level == 100 then
      event = current_level == 0 and windowShade.closed() or windowShade.open()
    elseif current_level ~= level then
      event = current_level < level and windowShade.opening() or windowShade.closing()
    end
    if event ~= nil then
      device:emit_event(event)
    end
    device.thread:call_with_delay(1, function(d)
      local current_level = device:get_latest_state(device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
        capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
      if current_level > 0 and current_level < 100 then
        device:emit_event(windowShade.partially_open())
      end
    end
    )
  end
end

local function window_shade_level_cmd(driver, device, command)
  local level = 100 - command.args.shadeLevel
  local current_level = device:get_latest_state(command.component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME, 0)
  print(current_level)
  if math.abs(command.args.shadeLevel - current_level) <= GLYDEA_MOVE_THRESHOLD then
    device:set_field(SAME_LEVEL_EVENT, true)
  end
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function window_shade_preset_cmd(driver, device, command)
  local level = device.preferences.presetPosition or device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or window_preset_defaults.PRESET_LEVEL
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local somfy_handler = {
  NAME = "SOMFY Device Handler",
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    },
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  can_handle = is_zigbee_window_shade,
}

return somfy_handler
