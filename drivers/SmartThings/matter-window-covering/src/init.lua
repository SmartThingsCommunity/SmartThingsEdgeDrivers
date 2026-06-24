-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--Note: Currently only support for window shades with the PositionallyAware Feature
--Note: No support for setting device into calibration mode, it must be done manually
local capabilities = require "st.capabilities"
local im = require "st.matter.interaction_model"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"

local battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}
local OP_STATUS_BITMAP = {
  idle = 0x00,
  opening = 0x01,
  closing = 0x02
}
local DEFAULT_PRESET_LEVEL = 50

local TARGET_LIFT_PERCENT = {
  TIMEOUT_DELAY_S = 120,
  TIMEOUT = "__target_lift_percent_timeout",
  STATE = "__target_lift_percent"
}

local TARGET_TILT_PERCENT = {
  TIMEOUT_DELAY_S = 120,
  TIMEOUT = "__target_tilt_percent_timeout",
  STATE = "__target_tilt_percent"
}

local TARGET_REACH_TOLERANCE = 0.5

--- Gets the current window shade status based on the lift and tilt positions.
---@param device any a Matter device object
---@return any status the current window shade status
local function get_idle_window_shade_status(device)
  -- Update the window shade status according to the lift and tilt positions.
  --   LIFT     TILT      Window Shade
  --   100      any       Open
  --   1-99     any       Partially Open
  --   0        1-100     Partially Open
  --   0        0         Closed
  --   0        nil       Closed
  --   nil      100       Open
  --   nil      1-99      Partially Open
  --   nil      0         Closed
  -- Note that lift or tilt may be nil if either the window shade does not
  -- support them or if they haven't been received from a device report yet.

  local lift_position = device:get_latest_state(
    "main",
    capabilities.windowShadeLevel.ID,
    capabilities.windowShadeLevel.shadeLevel.NAME
  )
  local tilt_position = device:get_latest_state(
    "main",
    capabilities.windowShadeTiltLevel.ID,
    capabilities.windowShadeTiltLevel.shadeTiltLevel.NAME
  )
  local reverse = device.preferences.reverse
  local windowShade = capabilities.windowShade.windowShade
  local status_event = windowShade.unknown()

  if lift_position == nil then
    if tilt_position == 0 then
      status_event = reverse and windowShade.open() or windowShade.closed()
    elseif tilt_position == 100 then
      status_event = reverse and windowShade.closed() or windowShade.open()
    else
      status_event = windowShade.partially_open()
    end
  elseif lift_position == 100 then
    status_event = reverse and windowShade.closed() or windowShade.open()
  elseif lift_position > 0 then
    status_event = windowShade.partially_open()
  elseif lift_position == 0 then
    if tilt_position == nil or tilt_position == 0 then
      status_event = reverse and windowShade.open() or windowShade.closed()
    elseif tilt_position > 0 then
      status_event = windowShade.partially_open()
    end
  end
  return status_event
end

--- Clears the cached target percentage and cancels any associated timeout.
--- @param device any a Matter device object
--- @param op_fields table a table containing operational field constants used for caching target percentages and timeouts.
local function clear_cached_data(device, op_fields)
  local current_timer = device:get_field(op_fields.TIMEOUT)
  if current_timer then
    device.thread:cancel_timer(current_timer)
  end
  device:set_field(op_fields.STATE, nil)
  device:set_field(op_fields.TIMEOUT, nil)
end

--- Tries to emit the idle window shade status if no target percentages are set.
--- @param device any a Matter device object
local function try_emit_idle_window_shade_status(device)
  if not device:get_field(TARGET_LIFT_PERCENT.STATE) and
   not device:get_field(TARGET_TILT_PERCENT.STATE) then
    device:emit_event(get_idle_window_shade_status(device))
  end
end

--- Caches the target percentage for a device and sets a timeout to clear it.
--- @param device any a Matter device object
--- @param data number the target percentage to cache
--- @param op_fields table a table containing operational field constants used for caching target percentages and timeouts.
local function cache_data_with_timeout(device, data, op_fields)
  device:set_field(op_fields.STATE, data)
  local previous_timer = device:get_field(op_fields.TIMEOUT)
  if previous_timer then
    device.thread:cancel_timer(previous_timer)
  end
  local new_timer = device.thread:call_with_delay(op_fields.TIMEOUT_DELAY_S, function()
    device:set_field(op_fields.STATE, nil)
    device:set_field(op_fields.TIMEOUT, nil)
    try_emit_idle_window_shade_status(device)
  end)
  device:set_field(op_fields.TIMEOUT, new_timer)
end

local function is_target_value_reached(current_value, target_value)
  if (target_value and math.abs(current_value - target_value) <= TARGET_REACH_TOLERANCE) then
    return true
  end
  return false
end

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  return find_default_endpoint(device, clusters.WindowCovering.ID)
end

local function match_profile(device, battery_supported)
  local lift_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.LIFT})
  local tilt_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.TILT})
  local profile_name = "window-covering"
  if #tilt_eps > 0 then
    profile_name = profile_name .. "-tilt"
    if #lift_eps == 0 then
      profile_name = profile_name .. "-only"
    end
  end

  if battery_supported == battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  elseif battery_supported == battery_support.BATTERY_LEVEL then
    profile_name = profile_name .. "-batteryLevel"
  end
  device:try_update_metadata({profile = profile_name})
end

local function device_init(driver, device)
  -- set unused fields to nil. These field settings can be removed after a single driver update.
  device:set_field("__preset_level_key", nil)
  device:set_field("__reverse_polarity", nil)

  device:set_component_to_endpoint_fn(component_to_endpoint)
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME) == nil then
    -- These should only ever be nil once (and at the same time) for already-installed devices
    -- It can be removed after migration is complete
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}}))
    local preset_position = device.preferences.presetPosition or DEFAULT_PRESET_LEVEL
    device:emit_event(capabilities.windowShadePreset.position(preset_position, {visibility = {displayed = false}}))
  end
  device:subscribe()
end

local function do_configure(driver, device)
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    local attribute_list_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
    attribute_list_read:merge(clusters.PowerSource.attributes.AttributeList:read())
    device:send(attribute_list_read)
  else
    match_profile(device, battery_support.NO_BATTERY)
  end
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  elseif device.matter_version.software ~= args.old_st_store.matter_version.software then
    local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
    if #battery_feature_eps > 0 then
      local attribute_list_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
      attribute_list_read:merge(clusters.PowerSource.attributes.AttributeList:read())
      device:send(attribute_list_read)
    else
      match_profile(device, battery_support.NO_BATTERY)
    end
  end
end

local function device_added(driver, device)
  device:emit_event(
    capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, {visibility = {displayed = false}})
  )
end

-- capability handlers
local function handle_preset(driver, device, cmd)
  local lift_value = device:get_latest_state(
    "main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME
  ) or DEFAULT_PRESET_LEVEL
  local hundredths_lift_percent = (100 - lift_value) * 100
  cache_data_with_timeout(device, lift_value, TARGET_LIFT_PERCENT)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(
    device, endpoint_id, hundredths_lift_percent
  ))
end

local function handle_set_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:emit_event_for_endpoint(endpoint_id, capabilities.windowShadePreset.position(cmd.args.position))
end

local function handle_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  if device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.LIFT}) then
    cache_data_with_timeout(device, device.preferences.reverse and 100 or 0, TARGET_LIFT_PERCENT)
  end
  if device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.TILT}) then
    cache_data_with_timeout(device, device.preferences.reverse and 100 or 0, TARGET_TILT_PERCENT)
  end
  device:send(device.preferences.reverse and
    clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id) or
    clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
  )
end

local function handle_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  if device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.LIFT}) then
    cache_data_with_timeout(device, device.preferences.reverse and 0 or 100, TARGET_LIFT_PERCENT)
  end
  if device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.TILT}) then
    cache_data_with_timeout(device, device.preferences.reverse and 0 or 100, TARGET_TILT_PERCENT)
  end
  device:send(device.preferences.reverse and
    clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id) or
    clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
  )
end

local function handle_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.WindowCovering.server.commands.StopMotion(device, endpoint_id))
end

-- move to shade level between 0-100
local function handle_shade_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local hundredths_lift_percentage = (100 - cmd.args.shadeLevel) * 100
  cache_data_with_timeout(device, cmd.args.shadeLevel, TARGET_LIFT_PERCENT)
  device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(
    device, endpoint_id, hundredths_lift_percentage
  ))
end

local function handle_step_shade_level(driver, device, cmd)
  local step = cmd.args.stepSize
  local latest_lift_percentage = device:get_latest_state(
    "main",
    capabilities.windowShadeLevel.ID,
    capabilities.windowShadeLevel.shadeLevel.NAME,
    0
  )
  local target_lift_percent = device:get_field(TARGET_LIFT_PERCENT.STATE) or latest_lift_percentage
  local updated_target_lift = utils.clamp_value(target_lift_percent + step, 0, 100)
  cache_data_with_timeout(device, updated_target_lift, TARGET_LIFT_PERCENT)
  driver:inject_capability_command(device, {
    capability = capabilities.windowShadeLevel.ID,
    component = cmd.component,
    command = capabilities.windowShadeLevel.commands.setShadeLevel.NAME,
    named_args = { shadeLevel = updated_target_lift }
  })
end

-- move to shade tilt level between 0-100
local function handle_shade_tilt_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local hundredths_tilt_percentage = (100 - cmd.args.level) * 100
  cache_data_with_timeout(device, cmd.args.level, TARGET_TILT_PERCENT)
  device:send(clusters.WindowCovering.server.commands.GoToTiltPercentage(
    device, endpoint_id, hundredths_tilt_percentage
  ))
end

-- attribute handlers
local function current_position_lift_percent_100ths_handler(driver, device, ib, response)
  if not ib.data.value then return end
  local lift_percent = 100 - math.floor(ib.data.value / 100)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(lift_percent))

  if is_target_value_reached(lift_percent, device:get_field(TARGET_LIFT_PERCENT.STATE)) then
    clear_cached_data(device, TARGET_LIFT_PERCENT)
    try_emit_idle_window_shade_status(device)
  end
end

local function current_position_tilt_percent_100ths_handler(driver, device, ib, response)
  if not ib.data.value then return end
  local tilt_percent = 100 - math.floor(ib.data.value / 100)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeTiltLevel.shadeTiltLevel(tilt_percent))

  if is_target_value_reached(tilt_percent, device:get_field(TARGET_TILT_PERCENT.STATE)) then
    clear_cached_data(device, TARGET_TILT_PERCENT)
    try_emit_idle_window_shade_status(device)
  end
end

local function target_position_lift_percent_100ths_handler(driver, device, ib, response)
  if type(ib.data.value) == "number" then
    local target_lift_percent = 100 - math.floor(ib.data.value / 100)
    local latest_lift_percentage = device:get_latest_state(
      "main",
      capabilities.windowShadeLevel.ID,
      capabilities.windowShadeLevel.shadeLevel.NAME
    )
    if latest_lift_percentage and is_target_value_reached(latest_lift_percentage, target_lift_percent) then
      clear_cached_data(device, TARGET_LIFT_PERCENT)
      try_emit_idle_window_shade_status(device)
    else
      cache_data_with_timeout(device, target_lift_percent, TARGET_LIFT_PERCENT)
    end
  end
end

local function target_position_tilt_percent_100ths_handler(driver, device, ib, response)
  if type(ib.data.value) == "number" then
    local target_tilt_percent = 100 - math.floor(ib.data.value / 100)
    local latest_tilt_percent = device:get_latest_state(
      "main",
      capabilities.windowShadeTiltLevel.ID,
      capabilities.windowShadeTiltLevel.shadeTiltLevel.NAME
    )
    if latest_tilt_percent and is_target_value_reached(latest_tilt_percent, target_tilt_percent) then
      clear_cached_data(device, TARGET_TILT_PERCENT)
      try_emit_idle_window_shade_status(device)
    else
      cache_data_with_timeout(device, target_tilt_percent, TARGET_TILT_PERCENT)
    end
  end
end

-- checks the current position of the shade
local function operational_status_handler(driver, device, ib, response)
  if not ib.data.value then return end
  local global_op_status = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL

  local reverse = device.preferences.reverse
  local windowShade = capabilities.windowShade.windowShade
  local status_event
  if global_op_status == OP_STATUS_BITMAP.idle then
    try_emit_idle_window_shade_status(device)
  elseif global_op_status == OP_STATUS_BITMAP.opening then
    status_event = reverse and windowShade.closing() or windowShade.opening()
  elseif global_op_status == OP_STATUS_BITMAP.closing then
    status_event = reverse and windowShade.opening() or windowShade.closing()
  else
    status_event = windowShade.unknown()
  end
  if status_event then
    device:emit_event_for_endpoint(ib.endpoint_id, status_event)
  end
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local function battery_charge_level_attr_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

local function power_source_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements or {}) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) is present.
    if attr.value == 0x0C then
      match_profile(device, battery_support.BATTERY_PERCENTAGE)
      return
    elseif attr.value == 0x0E then
      match_profile(device, battery_support.BATTERY_LEVEL)
      return
    end
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.WindowCovering.ID] = {
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_position_lift_percent_100ths_handler,
        [clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths.ID] = current_position_tilt_percent_100ths_handler,
        [clusters.WindowCovering.attributes.TargetPositionLiftPercent100ths.ID] = target_position_lift_percent_100ths_handler,
        [clusters.WindowCovering.attributes.TargetPositionTiltPercent100ths.ID] = target_position_tilt_percent_100ths_handler,
        [clusters.WindowCovering.attributes.OperationalStatus.ID] = operational_status_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = battery_charge_level_attr_handler,
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler,
      }
    },
  },
  subscribed_attributes = {
    [capabilities.windowShade.ID] = {
      clusters.WindowCovering.attributes.OperationalStatus
    },
    [capabilities.windowShadeLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths,
      clusters.WindowCovering.attributes.TargetPositionLiftPercent100ths,
    },
    [capabilities.windowShadeTiltLevel.ID] = {
      clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths,
      clusters.WindowCovering.attributes.TargetPositionTiltPercent100ths,
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    },
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel,
    },
  },
  capability_handlers = {
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = handle_preset,
      [capabilities.windowShadePreset.commands.setPresetPosition.NAME] = handle_set_preset,
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.close.NAME] = handle_close,
      [capabilities.windowShade.commands.open.NAME] = handle_open,
      [capabilities.windowShade.commands.pause.NAME] = handle_pause,
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = handle_shade_level,
    },
    [capabilities.statelessWindowShadeLevelStep.ID] = {
      [capabilities.statelessWindowShadeLevelStep.commands.stepShadeLevel.NAME] = handle_step_shade_level
    },
    [capabilities.windowShadeTiltLevel.ID] = {
      [capabilities.windowShadeTiltLevel.commands.setShadeTiltLevel.NAME] = handle_shade_tilt_level,
    },
  },
  supported_capabilities = {
    capabilities.windowShadeLevel,
    capabilities.windowShadeTiltLevel,
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.doorControl,
    capabilities.level,
    capabilities.battery,
    capabilities.batteryLevel,
  },
  sub_drivers = require("sub_drivers"),
  shared_device_thread_enabled = true,
}

local matter_driver = MatterDriver("matter-window-covering", matter_driver_template)
matter_driver:run()
