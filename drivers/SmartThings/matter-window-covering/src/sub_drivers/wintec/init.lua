-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"
--- If the ASSIGNED_CHILD_KEY field is populated for an endpoint, it should be
--- used as the key in the get_child_by_parent_assigned_key() function. This allows
--- multiple endpoints to associate with the same child device, though right now child
--- devices are keyed using only one endpoint id.
local ASSIGNED_CHILD_KEY = "__assigned_child_key"
local PROFILE_TABLE = "__profile_table"

local CURRENT_LIFT = "__current_lift"
local CURRENT_TILT = "__current_tilt"
local REVERSE_POLARITY = "__reverse_polarity"
local PRESET_LEVEL_KEY = "__preset_level_key"
local DEFAULT_PRESET_LEVEL = 50

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

function update_profile_table(device)
  local profile_table = {}
  for _, tilt_ep in pairs(device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.TILT})) do
    profile_table[tilt_ep] = "window-covering-tilt-only"
    for _, lift_ep in pairs(device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.LIFT})) do
      if tilt_ep == lift_ep then
        profile_table[tilt_ep] = "window-covering-top-bottom-control"
      end
    end
  end
  device:set_field(PROFILE_TABLE, profile_table, {persist = true})


  for key, value in pairs(profile_table) do
    device.log.info_with({hub_logs=true}, string.format("!!! key: %s, value: %s !!!", key, value))
  end

  return profile_table
end

function do_create_or_update(driver, device, device_num, ep_id, profile_table)
  local label_and_name = string.format("%s %d", device.label, device_num)
  local child_profile = profile_table[ep_id] or "window-covering"
  local existing_child_device = device:get_field(IS_PARENT_CHILD_DEVICE) and find_child(device, ep_id)
  
  device.log.info_with({hub_logs=true}, string.format("!!! do_create_or_update: %s !!!", child_profile))

  if not existing_child_device then
    driver:try_create_device({
      type = "EDGE_CHILD",
      label = label_and_name,
      profile = child_profile,
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%d", ep_id),
      vendor_provided_label = label_and_name
    })
  else
    existing_child_device:try_update_metadata({
      profile = child_profile,
      optional_component_capabilities = optional_component_capabilities
    })
  end
end

function find_child(parent_device, ep_id)
  parent_device.log.info_with({hub_logs=true}, string.format("!!! find_child !!!"))
  local assigned_key = parent_device:get_field(string.format("%s_%d", "__assigned_child_key", ep_id)) or ep_id
  return parent_device:get_child_by_parent_assigned_key(string.format("%d", assigned_key))
end

function create_or_update_child_devices(driver, device)
  device.log.info_with({hub_logs=true}, string.format("!!! create_or_update_child_devices !!!"))
  local default_endpoint_id = find_default_endpoint(device) 
  local server_cluster_ep_ids = device:get_endpoints(clusters.WindowCovering.ID)
  device.log.info_with({hub_logs=true}, string.format("!!! default_endpoint_id: %s !!!", default_endpoint_id))
  device.log.info_with({hub_logs=true}, string.format("!!! server_cluster_ep_ids: %s !!!", #server_cluster_ep_ids))
  if #server_cluster_ep_ids == 1 and server_cluster_ep_ids[1] == default_endpoint_id then -- no children will be created
    return
  end

  local profile_table = update_profile_table(device)

  table.sort(server_cluster_ep_ids)
  for device_num, ep_id in ipairs(server_cluster_ep_ids) do
    if ep_id ~= default_endpoint_id then -- don't create a child device that maps to the main endpoint
      do_create_or_update(driver, device, device_num, ep_id, profile_table)
    end
  end

  -- Persist so that the find_child function is always set on each driver init.
  device:set_field(IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_find_child(find_child)
end

local function device_init(driver, device)
  device.log.info_with({hub_logs=true}, string.format("!!! device_init !!!"))
  -- device:set_endpoint_to_component_fn(endpoint_to_component)
  -- device:set_component_to_endpoint_fn(component_to_endpoint)

  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME) == nil then
    -- These should only ever be nil once (and at the same time) for already-installed devices
    -- It can be removed after migration is complete
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}}))
    local preset_position = device:get_field(PRESET_LEVEL_KEY) or
      (device.preferences ~= nil and device.preferences.presetPosition) or
      DEFAULT_PRESET_LEVEL
    device:emit_event(capabilities.windowShadePreset.position(preset_position, {visibility = {displayed = false}}))
    device:set_field(PRESET_LEVEL_KEY, preset_position, {persist = true})
  end
  device:subscribe()
end

local function do_configure(driver, device)
  device.log.info_with({hub_logs=true}, string.format("!!! do_configure !!!"))
  create_or_update_child_devices(driver, device)

  local lift_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.LIFT})
  local tilt_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.TILT})
  local profile_name = "window-covering"
  if #tilt_eps > 0 then
    if #lift_eps == 0 then
      profile_name = profile_name .. "-tilt-only"
    else
      profile_name = profile_name .. "-top-bottom-control"
    end
  end
  device:try_update_metadata({profile = profile_name})
end

local function info_changed(driver, device, event, args)
  device.log.info_with({hub_logs=true}, string.format("!!! info_changed !!!"))
  if device.profile.id ~= args.old_st_store.profile.id then
    -- Profile has changed, resubscribe
    device:subscribe()
  elseif args.old_st_store.preferences.reverse ~= device.preferences.reverse then
    if device.preferences.reverse then
      device:set_field(REVERSE_POLARITY, true, { persist = true })
    else
      device:set_field(REVERSE_POLARITY, false, { persist = true })
    end
  else
    -- Something else has changed info (SW update, reinterview, etc.), so
    -- try updating profile as needed
    create_or_update_child_devices(driver, device)
  end
end

local function device_added(driver, device)
  device.log.info_with({hub_logs=true}, string.format("!!! device_added !!!"))
  device:emit_event(
    capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, {visibility = {displayed = false}})
  )
  device:set_field(REVERSE_POLARITY, false, { persist = true })
end










-- current lift/tilt percentage, changed to 100ths percent
local current_pos_handler = function(attribute)
  return function(driver, device, ib, response)
    device.log.info_with({hub_logs=true}, string.format("!!! current_pos_handler: %s !!!", ib.endpoint_id))
    if ib.data.value == nil then
      return
    end
    local windowShade = capabilities.windowShade.windowShade
    local position = 100 - math.floor(ib.data.value / 100)
    local reverse = device:get_field(REVERSE_POLARITY)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(position))

    if attribute == capabilities.windowShadeLevel.shadeLevel then
      device:set_field(CURRENT_LIFT, position)
    else
      device:set_field(CURRENT_TILT, position)
    end

    local lift_position = device:get_field(CURRENT_LIFT)
    local tilt_position = device:get_field(CURRENT_TILT)

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

    if lift_position == nil then
      if tilt_position == 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
      elseif tilt_position == 100 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())
      else
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
      end

    elseif lift_position == 100 then
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())

    elseif lift_position > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())

    elseif lift_position == 0 then
      if tilt_position == nil or tilt_position == 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
      elseif tilt_position > 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
      end
    end
  end
end

-- -- checks the current position of the shade
local function current_status_handler(driver, device, ib, response)
  device.log.info_with({hub_logs=true}, string.format("!!! current_status_handler: %s !!!", ib.endpoint_id))
  local windowShade = capabilities.windowShade.windowShade
  local reverse = device:get_field(REVERSE_POLARITY)
  local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
  if state == 1 then -- opening
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closing() or windowShade.opening())
  elseif state == 2 then -- closing
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.opening() or windowShade.closing())
  elseif state ~= 0 then -- unknown
    device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
  end
end

local function level_attr_handler(driver, device, ib, response)
  device.log.info_with({hub_logs=true}, string.format("!!! level_attr_handler: %s !!!", ib.endpoint_id))
  if ib.data.value ~= nil then
    --TODO should we invert this like we do for CurrentLiftPercentage100ths?
    local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(level))
  end
end







-- capability handlers
local function handle_preset(driver, device, cmd)
  device.log.info_with({hub_logs=true}, string.format("!!! handle_preset: %s !!!", ib.endpoint_id))
  local lift_value = device:get_latest_state(
    "main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME
  ) or DEFAULT_PRESET_LEVEL
  local hundredths_lift_percent = (100 - lift_value) * 100
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(
    device, endpoint_id, hundredths_lift_percent
  ))
end

local function handle_set_preset(driver, device, cmd)
  device.log.info_with({hub_logs=true}, string.format("!!! handle_set_preset: %s !!!", ib.endpoint_id))
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:set_field(PRESET_LEVEL_KEY, cmd.args.position)
  device:emit_event_for_endpoint(endpoint_id, capabilities.windowShadePreset.position(cmd.args.position))
end

local function handle_close(driver, device, cmd)
  device.log.info_with({hub_logs=true}, string.format("!!! handle_close: %s !!!", ib.endpoint_id))
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
  if device:get_field(REVERSE_POLARITY) then
    req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
  end
  device:send(req)
end

local function handle_open(driver, device, cmd)
  device.log.info_with({hub_logs=true}, string.format("!!! handle_open: %s !!!", ib.endpoint_id))
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
  if device:get_field(REVERSE_POLARITY) then
    req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
  end
  device:send(req)
end

local function handle_pause(driver, device, cmd)
  device.log.info_with({hub_logs=true}, string.format("!!! handle_pause: %s !!!", ib.endpoint_id))
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.WindowCovering.server.commands.StopMotion(device, endpoint_id))
end

local function handle_shade_level(driver, device, cmd)
  device.log.info_with({hub_logs=true}, string.format("!!! handle_shade_level !!!"))
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local lift_percentage_value = 100 - cmd.args.shadeLevel
  local hundredths_lift_percentage = lift_percentage_value * 100
  device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(
    device, endpoint_id, hundredths_lift_percentage
  ))
end

-- move to shade tilt level between 0-100
local function handle_shade_tilt_level(driver, device, cmd)
  device.log.info_with({hub_logs=true}, string.format("!!! handle_shade_tilt_level: %s !!!", ib.endpoint_id))
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local tilt_percentage_value = 100 - cmd.args.level
  local hundredths_tilt_percentage = tilt_percentage_value * 100
  device:send(clusters.WindowCovering.server.commands.GoToTiltPercentage(
    device, endpoint_id, hundredths_tilt_percentage
  ))
end










local wintec_handler = {
  NAME = "wintec",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = level_attr_handler,
      },
      [clusters.WindowCovering.ID] = {
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_pos_handler(capabilities.windowShadeLevel.shadeLevel),
        [clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths.ID] = current_pos_handler(capabilities.windowShadeTiltLevel.shadeTiltLevel),
        [clusters.WindowCovering.attributes.OperationalStatus.ID] = current_status_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = battery_charge_level_attr_handler,
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler,
      }
    }
  },
  subscribed_attributes = {
    [capabilities.windowShade.ID] = {
      clusters.WindowCovering.attributes.OperationalStatus
    },
    [capabilities.windowShadeLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths,
    },
    [capabilities.windowShadeTiltLevel.ID] = {
      clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths,
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
    [capabilities.windowShadeTiltLevel.ID] = {
      [capabilities.windowShadeTiltLevel.commands.setShadeTiltLevel.NAME] = handle_shade_tilt_level,
    },
  },
  can_handle = require("sub_drivers.wintec.can_handle"),
  shared_device_thread_enabled = true,
}

return wintec_handler