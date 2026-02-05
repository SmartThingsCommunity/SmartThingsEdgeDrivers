-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-------------------------------------------------------------------------------------
-- Matter Closures Sub Driver
-------------------------------------------------------------------------------------

local attribute_handlers = require "sub_drivers.closures.closure_handlers.attribute_handlers"
local capabilities = require "st.capabilities"
local capability_handlers = require "sub_drivers.closures.closure_handlers.capability_handlers"
local closure_fields = require "sub_drivers.closures.closure_utils.fields"
local clusters = require "st.matter.clusters"
local switch_utils = require "switch_utils.utils"

local ClosureLifecycleHandlers = {}

function ClosureLifecycleHandlers.device_init(driver, device)
  if device:supports_capability_by_id(capabilities.windowShade.ID) and
    device:get_latest_state("main", capabilities.windowShade.ID, capabilities.windowShade.supportedWindowShadeCommands.NAME) == nil then
    device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, {visibility = {displayed = false}}))
  end
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME) == nil then
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}}))
    local preset_position = device:get_field(closure_fields.PRESET_LEVEL_KEY) or
      (device.preferences ~= nil and device.preferences.presetPosition) or
      closure_fields.DEFAULT_PRESET_LEVEL
    device:emit_event(capabilities.windowShadePreset.position(preset_position, {visibility = {displayed = false}}))
    device:set_field(closure_fields.PRESET_LEVEL_KEY, preset_position, {persist = true})
  end

  device:set_component_to_endpoint_fn(switch_utils.component_to_endpoint)
  device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)

  device:extend_device("subscribe", switch_utils.subscribe)
  device:subscribe()
end

function ClosureLifecycleHandlers.device_added(driver, device)
  device:set_field(closure_fields.REVERSE_POLARITY, false, { persist = true })
  switch_utils.handle_electrical_sensor_info(device)
end

local closures_handler = {
  NAME = "closures",
  lifecycle_handlers = {
    init = ClosureLifecycleHandlers.device_init,
    added = ClosureLifecycleHandlers.device_added
  },
  matter_handlers = {
    attr = {
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = attribute_handlers.level_attr_handler,
      },
      [clusters.WindowCovering.ID] = {
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = attribute_handlers.current_pos_handler(capabilities.windowShadeLevel.shadeLevel),
        [clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths.ID] = attribute_handlers.current_pos_handler(capabilities.windowShadeTiltLevel.shadeTiltLevel),
        [clusters.WindowCovering.attributes.OperationalStatus.ID] = attribute_handlers.current_status_handler
      },
    },
  },
  capability_handlers = {
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = capability_handlers.handle_preset,
      [capabilities.windowShadePreset.commands.setPresetPosition.NAME] = capability_handlers.handle_set_preset
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.close.NAME] = capability_handlers.handle_close,
      [capabilities.windowShade.commands.open.NAME] = capability_handlers.handle_open,
      [capabilities.windowShade.commands.pause.NAME] = capability_handlers.handle_pause
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = capability_handlers.handle_shade_level
    },
    [capabilities.windowShadeTiltLevel.ID] = {
      [capabilities.windowShadeTiltLevel.commands.setShadeTiltLevel.NAME] = capability_handlers.handle_shade_tilt_level
    },
  },
  can_handle = require("sub_drivers.closures.can_handle")
}

return closures_handler
