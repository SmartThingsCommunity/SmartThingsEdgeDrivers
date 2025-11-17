-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local window_shade_utils = require "window_shade_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"

local Basic = zcl_clusters.Basic
local Level = zcl_clusters.Level
local PowerConfiguration = zcl_clusters.PowerConfiguration
local WindowCovering = zcl_clusters.WindowCovering

local DEFAULT_LEVEL = 0


-- Commands
local function window_shade_set_level(device, command, level)
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or DEFAULT_LEVEL
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  -- Opening or Closing
  local windowShade = capabilities.windowShade.windowShade
  device:emit_event(level > current_level and windowShade.opening() or windowShade.closing())
  -- Send Zigbee command
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 100 - level))
end

local function window_shade_level_cmd_handler(driver, device, command)
  local level = command.args.shadeLevel
  window_shade_set_level(device, command, level)
end

local function window_shade_preset_cmd(driver, device, command)
  local level = window_shade_utils.get_preset_level(device, command.component)
  window_shade_set_level(device, command, level)
end

local function window_shade_pause_cmd(driver, device, command)
  local window_shade_state = device:get_latest_state("main", capabilities.windowShade.ID, capabilities.windowShade.windowShade.NAME) or "unknown"
  if window_shade_state == "opening" or window_shade_state == "closing" then
    device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
  else
    device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  end
end

local function window_shade_open_cmd(driver, device, command)
  device:emit_event(capabilities.windowShade.windowShade.opening())
  device:send_to_component(command.component, WindowCovering.server.commands.UpOrOpen(device))
end

local function window_shade_close_cmd(driver, device, command)
  device:emit_event(capabilities.windowShade.windowShade.closing())
  device:send_to_component(command.component, WindowCovering.server.commands.DownOrClose(device))
end

-- Common
local function handle_window_shade(device, current_level)
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
  handle_window_shade(device, level)
end

local function level_attr_handler(driver, device, value, zb_rx)
  local level = utils.round((value.value / 254.0) * 100)
  local windowShade = capabilities.windowShade.windowShade
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or DEFAULT_LEVEL

  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  -- If the last level equals the current reported level then it is assumed we have reached our destination.
  if current_level == level then
    handle_window_shade(device, current_level)
  else
    device:emit_event(level > current_level and windowShade.opening() or windowShade.closing())
  end
end

local do_refresh = function(self, device)
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(Basic.attributes.SWBuildID:read(device))
end

local axis_handler_version = {
  NAME = "AXIS Gear Handler with version",
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
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = level_attr_handler
      },
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  can_handle = require("axis.axis_version.can_handle"),
}

return axis_handler_version
