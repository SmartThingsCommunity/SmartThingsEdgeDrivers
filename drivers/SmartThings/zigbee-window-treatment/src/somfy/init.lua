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
local utils = require "st.utils"
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local WindowCovering = zcl_clusters.WindowCovering

local GLYDEA_MOVE_THRESHOLD = 3

local ZIGBEE_WINDOW_SHADE_FINGERPRINTS = {
    { mfr = "SOMFY", model = "Glydea Ultra Curtain" },
    { mfr = "SOMFY", model = "Sonesse 30 WF Roller" },
    { mfr = "SOMFY", model = "Sonesse 40 Roller" }
}

local MOVE_LESS_THAN_THRESHOLD = "_sameLevelEvent"
local FINAL_STATE_POLL_TIMER = "_finalStatePollTimer"

local is_zigbee_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_WINDOW_SHADE_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local function overwrite_existing_timer_if_needed(device, new_timer)
  local old_timer = device:get_field(FINAL_STATE_POLL_TIMER)
  if old_timer ~= nil then
    device.thread:cancel_timer(old_timer)
  end
  device:set_field(FINAL_STATE_POLL_TIMER, new_timer)
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  -- Somfy Device report as invert value
  local level = 100 - value.value
  local current_level = device:get_latest_state(device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
    capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  local windowShade = capabilities.windowShade.windowShade
  local is_conditional_same_level_event = device:get_field(MOVE_LESS_THAN_THRESHOLD)
  -- If user wanted to change shadeLevel by value below acceptable threshold, accept same level event. In every other case, ignore it
  if (current_level == nil or current_level ~= level) or (is_conditional_same_level_event == nil or is_conditional_same_level_event ) then
    device:set_field(MOVE_LESS_THAN_THRESHOLD, false)
    current_level = current_level or 0
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
    local event = nil
    if level == 0 or level == 100 then
      event = level == 0 and windowShade.closed() or windowShade.open()
    elseif current_level ~= level then
      event = current_level < level and windowShade.opening() or windowShade.closing()
      local timer = device.thread:call_with_delay(2, function(d)
        local current_level = device:get_latest_state(device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
          capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
        if current_level > 0 and current_level < 100 then
          device:emit_event(windowShade.partially_open())
        end
      end
      )
      overwrite_existing_timer_if_needed(device, timer)
    end
    if event ~= nil then
      device:emit_event(event)
    end
  end
end

--[[
 Observation from PKacprowiczS:
	I've been working recently with the device, and I've noticed that when setting a shadeLevel below
	"accepted" threshold (3 +/- currentLevel), it doesn't send any message with level, as it used to
	back then, when I was working on its DTH. Since my current sample has newer firmware, I'm guessing
	that behavior was changed by the manufacturer. Either way, in addition to including additional handler,
	I've also left "DTH style" of handling the scenario, just in case.
--]]
local function movement_ended_handler(driver, device, value, zb_rx)
  local is_conditional_same_level_event = device:get_field(MOVE_LESS_THAN_THRESHOLD)
  if is_conditional_same_level_event == nil or is_conditional_same_level_event then
    device:set_field(MOVE_LESS_THAN_THRESHOLD, false)
    local current_level = device:get_latest_state(device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
      capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or 0
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(current_level))
  end
end

local function window_shade_level_cmd(driver, device, command)
  local level = utils.clamp_value(command.args.shadeLevel, 0, 100)
  local current_level = device:get_latest_state(command.component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME, 0)
  if math.abs(level - current_level) <= GLYDEA_MOVE_THRESHOLD then
    device:set_field(MOVE_LESS_THAN_THRESHOLD, true)
  end
  level = 100 - level
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function window_shade_preset_cmd(driver, device, command)
  local level = device.preferences.presetPosition or device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or window_preset_defaults.PRESET_LEVEL
  command.args.shadeLevel = level
  window_shade_level_cmd(driver, device, command)
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
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler,
        [WindowCovering.attributes.PhysicalClosedLimitLift.ID] = movement_ended_handler
      }
    }
  },
  can_handle = is_zigbee_window_shade,
}

return somfy_handler
