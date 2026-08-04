-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local log = require "log"
local version = require "version"
local embedded_cluster_utils = require "sub_drivers.closure.closure_utils.embedded_cluster_utils"

if version.api < 20 then
  clusters.ClosureControl = require "embedded_clusters.ClosureControl"
  clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"
  clusters.Global = require "embedded_clusters.Global"
end

if version.api < 16 then
  clusters.Descriptor = require "embedded_clusters.Descriptor"
end


local fields = require "sub_drivers.closure.closure_utils.fields"
local closure_utils = require "sub_drivers.closure.closure_utils.utils"
local attribute_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
local capability_handlers = require "sub_drivers.closure.closure_handlers.capability_handlers"

-- ---------------------------------------------------------------------------
-- Lifecycle handlers
-- ---------------------------------------------------------------------------

local ClosureLifecycleHandlers = {}

function ClosureLifecycleHandlers.device_init(driver, device)
  device:set_component_to_endpoint_fn(closure_utils.component_to_endpoint)
  device:set_endpoint_to_component_fn(closure_utils.endpoint_to_component)
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID,
      capabilities.windowShadePreset.position.NAME) == nil then
    device:emit_event(capabilities.windowShadePreset.supportedCommands(
      {"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}}
    ))
    local preset_position = device:get_field(fields.PRESET_LEVEL_KEY) or
      (device.preferences ~= nil and device.preferences.presetPosition) or
      fields.DEFAULT_PRESET_LEVEL
    device:emit_event(capabilities.windowShadePreset.position(
      preset_position, {visibility = {displayed = false}}
    ))
    device:set_field(fields.PRESET_LEVEL_KEY, preset_position, {persist = true})
  end
  device:extend_device("subscribe", closure_utils.subscribe)
  device:subscribe()
end

function ClosureLifecycleHandlers.device_added(driver, device)
  if device:supports_capability_by_id(capabilities.windowShade.ID) then
    device:emit_event(
      capabilities.windowShade.supportedWindowShadeCommands(
        {"open", "close", "pause"}, {visibility = {displayed = false}}
      )
    )
  end
  device:set_field(fields.REVERSE_POLARITY, false, {persist = true})
end

function ClosureLifecycleHandlers.do_configure(driver, device)
  if #embedded_cluster_utils.get_endpoints(device, clusters.Descriptor.ID) == 0 then
    log.warn(
      "Descriptor cluster not implemented on ClosureControl endpoint, " ..
      "cannot read TagList to determine closure type"
    )
    device:set_field(fields.CLOSURE_TAG, fields.closure_tag_list.NA, {persist = true})
  end

  local battery_feature_eps = device:get_endpoints(
    clusters.PowerSource.ID,
    {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
  )
  if #battery_feature_eps == 0 then
    device:set_field(fields.CLOSURE_BATTERY_SUPPORT, fields.battery_support.NO_BATTERY, {persist = true})
    closure_utils.match_profile(device)
  end
end

function ClosureLifecycleHandlers.info_changed(driver, device, event, args)
  if not closure_utils.deep_equals(
    device.profile, args.old_st_store.profile, {ignore_functions = true}
  ) then
    device:subscribe()
  elseif args.old_st_store.preferences.reverse ~= device.preferences.reverse then
    if device.preferences.reverse then
      device:set_field(fields.REVERSE_POLARITY, true,  {persist = true})
    else
      device:set_field(fields.REVERSE_POLARITY, false, {persist = true})
    end
  end
end

-- ---------------------------------------------------------------------------
-- Subdriver template
-- ---------------------------------------------------------------------------

local closure_handler = {
  NAME = "Closure Handler",
  lifecycle_handlers = {
    init = ClosureLifecycleHandlers.device_init,
    added = ClosureLifecycleHandlers.device_added,
    doConfigure = ClosureLifecycleHandlers.do_configure,
    infoChanged = ClosureLifecycleHandlers.info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.ClosureControl.ID] = {
        [clusters.ClosureControl.attributes.MainState.ID] = attribute_handlers.main_state_attr_handler,
        [clusters.ClosureControl.attributes.OverallCurrentState.ID] = attribute_handlers.overall_current_state_attr_handler,
        [clusters.ClosureControl.attributes.OverallTargetState.ID] = attribute_handlers.overall_target_state_attr_handler,
      },
      [clusters.ClosureDimension.ID] = {
        [clusters.ClosureDimension.attributes.CurrentState.ID] = attribute_handlers.closure_dimension_current_state_handler,
      },
      [clusters.Descriptor.ID] = {
        [clusters.Descriptor.attributes.TagList.ID] = attribute_handlers.tag_list_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = attribute_handlers.power_source_attribute_list_handler,
      },
    },
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.close.NAME] = capability_handlers.handle_close,
      [capabilities.windowShade.commands.open.NAME] = capability_handlers.handle_open,
      [capabilities.windowShade.commands.pause.NAME] = capability_handlers.handle_pause,
    },
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.open.NAME] = capability_handlers.handle_open,
      [capabilities.doorControl.commands.close.NAME] = capability_handlers.handle_close,
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = capability_handlers.handle_shade_level,
    },
    [capabilities.level.ID] = {
      [capabilities.level.commands.setLevel.NAME] = capability_handlers.handle_level,
    },
  },
  can_handle = require("sub_drivers.closure.can_handle"),
}

return closure_handler
