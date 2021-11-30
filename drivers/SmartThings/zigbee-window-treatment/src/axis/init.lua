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
local device_management = require "st.zigbee.device_management"
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local Basic = zcl_clusters.Basic
local Level = zcl_clusters.Level
local PowerConfiguration = zcl_clusters.PowerConfiguration
local WindowCovering = zcl_clusters.WindowCovering

local SOFTWARE_VERSION = "software_version"
local DEFAULT_LEVEL = 0

local is_zigbee_window_shade = function(opts, driver, device)
  if device:get_manufacturer() == "AXIS" then
    return true
  end
  return false
end

-- Commands
local function window_shade_set_level(driver, device, command, level)
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or DEFAULT_LEVEL
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  -- Opening or Closing
  local windowShade = capabilities.windowShade.windowShade
  device:emit_event(level > current_level and windowShade.opening() or windowShade.closing())
  -- Send Zigbee command
  local shade_level = math.floor(level/100.0 * 254)
  device:send_to_component(command.component, Level.server.commands.MoveToLevelWithOnOff(device, shade_level))
end

local function window_shade_level_cmd_handler(driver, device, command)
  local level = command.args.shadeLevel
  window_shade_set_level(driver, device, command, level)
end

local function window_shade_preset_cmd(driver, device, command)
  local level = device.preferences and device.preferences.presetPosition or window_preset_defaults.PRESET_LEVEL
  window_shade_set_level(driver, device, command, level)
end

local function window_shade_pause_cmd(driver, device, command)
  device.thread:call_with_delay(5, function(d)
    device:send(Level.attributes.CurrentLevel:read(device))
    end
  )
end

local function window_shade_open_cmd(driver, device, command)
  window_shade_set_level(driver, device, command, 100)
end

local function window_shade_close_cmd(driver, device, command)
  window_shade_set_level(driver, device, command, 0)
end

-- Common
local function handle_window_shade(driver, device, zb_rx, current_level)
  local windowShade = capabilities.windowShade.windowShade
  if current_level > 0 and current_level < 99 then
    device:emit_event(windowShade.partially_open())
  elseif current_level >= 99 then
    device:emit_event(windowShade.open())
  else
    device:emit_event(windowShade.closed())
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = 100 - value.value
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  handle_window_shade(driver, device, zb_rx, level)
end

local function level_attr_handler(driver, device, value, zb_rx)
  local level = math.floor((value.value / 254.0 * 100) + 0.5)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  handle_window_shade(driver, device, zb_rx, level)
end

local do_refresh = function(self, device)
  device:send(Level.attributes.CurrentLevel:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(Basic.attributes.SWBuildID:read(device))
end

-- Attr Handlers
local function basic_software_version_attr_handler(driver, device, value, zb_rx)
  local version = tonumber(value.value, 16)
  -- Spec limits bytes upto 16 bytes
  device:set_field(SOFTWARE_VERSION, version, {persist = true})
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(Level.attributes.CurrentLevel:configure_reporting(device, 1, 3600, 1))
  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui))
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(device, 1, 3600, 1))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 1, 3600, 1))
end

local device_added = function(self, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}))
  device:set_field(SOFTWARE_VERSION, 0)
  device:send(Basic.attributes.SWBuildID:read(device))
end

local axis_handler = {
  NAME = "AXIS Gear Handler",
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd_handler
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
      [capabilities.windowShade.commands.pause.NAME] = window_shade_pause_cmd
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.SWBuildID.ID] = basic_software_version_attr_handler
      },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = level_attr_handler
      },
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
  },
  sub_drivers = { require("axis.axis_version") },
  can_handle = is_zigbee_window_shade,
}

return axis_handler
