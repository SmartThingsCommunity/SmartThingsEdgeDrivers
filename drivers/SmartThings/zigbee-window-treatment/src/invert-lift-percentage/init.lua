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
local zcl_clusters = require "st.zigbee.zcl.clusters"

local WindowCovering = zcl_clusters.WindowCovering

local SHADE_SET_STATUS = "shade_set_status"

local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = 100 - value.value
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  local windowShade = capabilities.windowShade.windowShade
  if level == -155 then -- unknown position
    device:emit_event(windowShade.unknown())
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(100))
  elseif level == 0 then
    device:emit_event(windowShade.closed())
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
  elseif level == 100 then
    device:emit_event(windowShade.open())
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(100))
  else
    if current_level ~= level or current_level == nil then
      current_level = current_level or 0
      device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
      local event = nil
      if current_level ~= level then
        event = current_level < level and windowShade.opening() or windowShade.closing()
      end
      if event ~= nil then
        device:emit_event(event)
      end
    end
    local set_status_timer = device:get_field(SHADE_SET_STATUS)
    if set_status_timer then
      device.thread:cancel_timer(set_status_timer)
      device:set_field(SHADE_SET_STATUS, nil)
    end
    local set_window_shade_status = function()
      local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
      if current_level == 0 then
        device:emit_event(windowShade.closed())
      elseif current_level == 100 then
        device:emit_event(windowShade.open())
      else
        device:emit_event(windowShade.partially_open())
      end
    end
    set_status_timer = device.thread:call_with_delay(1, set_window_shade_status)
    device:set_field(SHADE_SET_STATUS, set_status_timer)
  end
end

local function set_shade_level(device, value, command)
  local level = 100 - value
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function window_shade_level_cmd(driver, device, command)
  set_shade_level(device, command.args.shadeLevel, command)
end

local function window_shade_preset_cmd(driver, device, command)
  if device.preferences ~= nil and device.preferences.presetPosition ~= nil then
    set_shade_level(device, device.preferences.presetPosition, command)
  end
end

local ikea_window_treatment = {
  NAME = "inverted lift percentage",
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "IKEA of Sweden" or
      device:get_manufacturer() == "Smartwings" or
      device:get_manufacturer() == "Insta GmbH"
  end
}

return ikea_window_treatment
