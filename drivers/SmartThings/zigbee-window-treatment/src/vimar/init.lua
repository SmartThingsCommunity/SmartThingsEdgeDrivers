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
local windowShade = capabilities.windowShade.windowShade

-- VIMAR WINDOW SHADES BEHAVIOR
-- 1. Open/Close/SetToLevel command is invoked normally
-- 2. When shades are moving there is no current position update
-- 3. When shades stops, a new position update is sent with the new lift position

local VIMAR_SHADES_OPENING = "_vimarShadesOpening"
local VIMAR_SHADES_CLOSING = "_vimarShadesClosing"

local ZIGBEE_WINDOW_SHADE_FINGERPRINTS = {
    { mfr = "Vimar", model = "Window_Cov_v1.0" },
    { mfr = "Vimar", model = "Window_Cov_Module_v1.0" }
}

-- UTILS to check manufacturer details
local is_zigbee_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_WINDOW_SHADE_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

-- ATTRIBUTE HANDLER FOR CurrentPositionLiftPercentage
local function current_position_attr_handler(driver, device, value, zb_rx)
  -- Shade level is inverted
  local level = 100 - value.value

  -- Clear states
  device:set_field(VIMAR_SHADES_CLOSING, false)
  device:set_field(VIMAR_SHADES_OPENING, false)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))

  -- Assumption: Vimar shades are not moving anymore because the device sent the notification
  local event = nil
  -- Current level is 0 or 100
  if level == 0 or level == 100 then
    event = level == 0 and windowShade.closed() or windowShade.open()
  else
  -- Ignore current_shades_level = level / current_shades_level != level
    device.thread:call_with_delay(2, function(d)
      local current_shades_level = device:get_latest_state(
        device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
        capabilities.windowShadeLevel.ID,
        capabilities.windowShadeLevel.shadeLevel.NAME,
        0
      )
      -- Set as partially open
      if current_shades_level > 0 and current_shades_level < 100 then
        device:emit_event(windowShade.partially_open())
      end
    end)
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

-- COMMAND HANDLER for Pause
local function window_shade_pause_handler(driver, device, command)
    device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
end

-- COMMAND HANDLER for SetLevel
local function window_shade_set_level_handler(driver, device, command)
  local level = utils.clamp_value(command.args.shadeLevel, 0, 100)
  local current_shades_level = device:get_latest_state(command.component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME, 0)
  local vimar_opening = device:get_field(VIMAR_SHADES_OPENING)
  local vimar_closing = device:get_field(VIMAR_SHADES_CLOSING)

  -- User wants to change the current level when shades are currently moving
  -- in this case, the roller shutter ignores the command
  if current_shades_level ~= level and (vimar_opening or vimar_closing) then
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(current_shades_level))
    return
  end

  if current_shades_level > level then
    device:set_field(VIMAR_SHADES_CLOSING, true)
    device:emit_event(windowShade.closing())
  elseif current_shades_level < level then
    device:set_field(VIMAR_SHADES_OPENING, true)
    device:emit_event(windowShade.opening())
  end

  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))

  level = 100 - level
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

-- COMMAND HANDLER for Open
local function window_shade_open_handler(driver, device, command)
  command.args.shadeLevel = 100
  window_shade_set_level_handler(driver, device, command)
end

-- COMMAND HANDLER for Close
local function window_shade_close_handler(driver, device, command)
  command.args.shadeLevel = 0
  window_shade_set_level_handler(driver, device, command)
end

-- COMMAND HANDLER for PresetPosition
local function window_shade_preset_handler(driver, device, command)
  local level = device.preferences.presetPosition or device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or window_preset_defaults.PRESET_LEVEL
  command.args.shadeLevel = level
  window_shade_set_level_handler(driver, device, command)
end

-- INIT HANDLER with status checker
local device_init = function(self, device)
  -- Reset Status
  device:set_field(VIMAR_SHADES_CLOSING, false)
  device:set_field(VIMAR_SHADES_OPENING, false)
end

-- DRIVER HANDLER CONFIGURATION
local vimar_handler = {
  NAME = "Vimar Zigbee Window Shades",
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_set_level_handler
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_handler,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_handler,
      [capabilities.windowShade.commands.pause.NAME] = window_shade_pause_handler,
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_handler
    },
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      },
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = is_zigbee_window_shade,
}

return vimar_handler
