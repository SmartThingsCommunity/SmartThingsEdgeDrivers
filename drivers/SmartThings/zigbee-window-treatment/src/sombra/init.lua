-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local utils = require "st.utils"
local window_shade_utils = require "window_shade_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local WindowCovering = zcl_clusters.WindowCovering

local SOMBRA_SHADES_OPENING = "_sombraShadesOpening"
local SOMBRA_SHADES_CLOSING = "_sombraShadesClosing"

local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = value.value
  local component = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value)
  local current_level = device:get_latest_state(component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or 0

  device:set_field(SOMBRA_SHADES_CLOSING, false)
  device:set_field(SOMBRA_SHADES_OPENING, false)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))

  local windowShade = capabilities.windowShade.windowShade
  if level == 0 or level == 100 then
    device:emit_event(level == 0 and windowShade.closed() or windowShade.open())
  else
    local event = current_level < level and windowShade.opening() or windowShade.closing()
    device:emit_event(event)
    device.thread:call_with_delay(2, function()
      local latest_level = device:get_latest_state(component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME, 0)
      if latest_level > 0 and latest_level < 100 then
        device:emit_event(windowShade.partially_open())
      end
    end)
  end
end

local function window_shade_pause_handler(driver, device, command)
  device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
end

local function window_shade_set_level_handler(driver, device, command)
  local level = utils.clamp_value(command.args.shadeLevel, 0, 100)
  local current_shades_level = device:get_latest_state(command.component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME, 0)
  local sombra_opening = device:get_field(SOMBRA_SHADES_OPENING)
  local sombra_closing = device:get_field(SOMBRA_SHADES_CLOSING)

  if current_shades_level ~= level and (sombra_opening or sombra_closing) then
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(current_shades_level))
    return
  end

  if current_shades_level > level then
    device:set_field(SOMBRA_SHADES_CLOSING, true)
    device:emit_event(capabilities.windowShade.windowShade.closing())
  elseif current_shades_level < level then
    device:set_field(SOMBRA_SHADES_OPENING, true)
    device:emit_event(capabilities.windowShade.windowShade.opening())
  end

  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function window_shade_open_handler(driver, device, command)
  command.args.shadeLevel = 100
  window_shade_set_level_handler(driver, device, command)
end

local function window_shade_close_handler(driver, device, command)
  command.args.shadeLevel = 0
  window_shade_set_level_handler(driver, device, command)
end

local function window_shade_preset_handler(driver, device, command)
  local level = window_shade_utils.get_preset_level(device, command.component)
  command.args.shadeLevel = level
  window_shade_set_level_handler(driver, device, command)
end

local function device_init(self, device)
  device:set_field(SOMBRA_SHADES_CLOSING, false)
  device:set_field(SOMBRA_SHADES_OPENING, false)

  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME) == nil then

    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, { visibility = { displayed = false }}))
    local preset_position = window_shade_utils.get_preset_level(device, "main")
    device:emit_event(capabilities.windowShadePreset.position(preset_position, { visibility = { displayed = false }}))
    device:set_field(window_shade_utils.PRESET_LEVEL_KEY, preset_position, { persist = true })
  end
end

local sombra_handler = {
  NAME = "Sombra Shades Zigbee Window Shade",
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
    }
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = require("sombra.can_handle")
}

return sombra_handler
