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

--Note: Currently only support for window shades with the PositionallyAware Feature
--Note: No support for setting device into calibration mode, it must be done manually

local capabilities = require "st.capabilities"
local im = require "st.matter.interaction_model"
local log = require "log"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"

clusters.ClosureControl = require "embedded_clusters.ClosureControl"
clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"

local CURRENT_LIFT = "__current_lift"
local CURRENT_TILT = "__current_tilt"
local battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}
local REVERSE_POLARITY = "__reverse_polarity"
local PRESET_LEVEL_KEY = "__preset_level_key"
local DEFAULT_PRESET_LEVEL = 50
-- ClosureControl state cache key. A table is stored for each endpoint:
--   { main = <MainStateEnum>, current = <CurrentPositionEnum>, target = <TargetPositionEnum> }
local CLOSURE_CONTROL_STATE_CACHE = "__closure_control_state_cache"
local CLOSURE_BATTERY_SUPPORT = "__closure_battery_support"
local CLOSURE_TAG = "__closure_tag"
local closure_tag_list = {
  NA          = "N/A",
  COVERING    = "COVERING",
  WINDOW      = "WINDOW",
  BARRIER     = "BARRIER",
  CABINET     = "CABINET",
  GATE        = "GATE",
  GARAGE_DOOR = "GARAGE_DOOR",
  DOOR        = "DOOR",
}

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

local function get_closure_dimension_eps(device)
  local eps = device:get_endpoints(clusters.ClosureDimension.ID) or {}
  table.sort(eps)
  local result = {}
  for _, ep in ipairs(eps) do
    if ep ~= 0 then
      table.insert(result, ep)
      if #result >= 4 then break end
    end
  end
  return result
end

local function endpoint_to_component(device, ep_id)
  local dim_eps = get_closure_dimension_eps(device)
  if #dim_eps > 1 then
    local is_door_type = device:supports_capability_by_id(capabilities.doorControl.ID)
    local prefix = is_door_type and "door" or "windowShade"
    for i, ep in ipairs(dim_eps) do
      if ep == ep_id then
        return prefix .. i
      end
    end
  end
  return "main"
end

local function component_to_endpoint(device, component_name)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  if #device:get_endpoints(clusters.ClosureControl.ID) > 0 then
    local dim_eps = get_closure_dimension_eps(device)
    if #dim_eps > 1 then
      local comp_num = tonumber(component_name:match("(%d+)$"))
      if comp_num and dim_eps[comp_num] then
        return dim_eps[comp_num]
      end
    end
    return find_default_endpoint(device, clusters.ClosureControl.ID)
  end
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

local function match_profile_for_closure(device)
  if not device:get_field(CLOSURE_TAG) or not device:get_field(CLOSURE_BATTERY_SUPPORT) then
    log.warn("Closure tag or battery support not set yet, cannot match profile")
    return
  end
  local tag = device:get_field(CLOSURE_TAG)
  local profile_name
  local is_door_type = true
  if tag == closure_tag_list.GATE then
    profile_name = "gate"
  elseif tag == closure_tag_list.GARAGE_DOOR then
    profile_name = "garage-door"
  elseif tag == closure_tag_list.DOOR then
    profile_name = "door"
  else
    -- COVERING, WINDOW, BARRIER, CABINET, NA -> generic covering profile
    profile_name = "covering"
    is_door_type = false
  end

  local optional_caps = {}

  local closure_battery = device:get_field(CLOSURE_BATTERY_SUPPORT)
  if closure_battery == battery_support.BATTERY_PERCENTAGE then
    table.insert(optional_caps, {"main", {capabilities.battery.ID}})
  elseif closure_battery == battery_support.BATTERY_LEVEL then
    table.insert(optional_caps, {"main", {capabilities.batteryLevel.ID}})
  end

  -- ClosureDimension capabilities: windowShadeLevel (covering) or level (door types)
  local dim_eps = get_closure_dimension_eps(device)
  if #dim_eps > 0 then
    local dim_cap = is_door_type and capabilities.level.ID or capabilities.windowShadeLevel.ID
    if #dim_eps == 1 then
      -- Single ClosureDimension: enable the capability on the main component.
      local found_main = false
      for _, entry in ipairs(optional_caps) do
        if entry[1] == "main" then
          table.insert(entry[2], dim_cap)
          found_main = true
          break
        end
      end
      if not found_main then
        table.insert(optional_caps, {"main", {dim_cap}})
      end
    else
      -- Multiple ClosureDimensions: enable one optional component+capability per closure panel.
      local prefix = is_door_type and "door" or "windowShade"
      for i = 1, math.min(#dim_eps, 4) do
        table.insert(optional_caps, {prefix .. i, {dim_cap}})
      end
    end
  end

  device:try_update_metadata({
    profile = profile_name,
    optional_component_capabilities = #optional_caps > 0 and optional_caps or nil,
  })
end

--- Deeply compare two values.
--- Handles metatables. Can optionally ignore cycle checking and/or function differences.
---
--- @param a any
--- @param b any
--- @param opts table|nil { ignore_functions = boolean, ignore_cycles = boolean }
--- @param seen table|nil
--- @return boolean
local function deep_equals(a, b, opts, seen)
  if a == b then return true end -- same object
  if type(a) ~= type(b) then return false end -- different type
  if type(a) == "function" and opts and opts.ignore_functions then return true end
  if type(a) ~= "table" then return false end -- same type but not table, thus was already compared

  -- check for cycles in table references and preserve reference topology.
  if not (opts and opts.ignore_cycles) then
    seen = seen or {}
    seen[a] = seen[a] or {}
    if seen[a][b] then
      return seen[a][b]
    end
    seen[a][b] = true
  end

  -- Compare keys/values from a
  for k, v in pairs(a) do
    if not deep_equals(v, b[k], opts, seen) then
      return false
    end
  end

  -- Ensure b doesn't have extra keys
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end

  -- Compare metatables
  local mt_a = getmetatable(a)
  local mt_b = getmetatable(b)
  return deep_equals(mt_a, mt_b, opts, seen)
end

local function device_init(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
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
  local closure_control_eps = device:get_endpoints(clusters.ClosureControl.ID)
  if #closure_control_eps > 0 then
    -- read TagList to determine the closure type
    if #device:get_endpoints(clusters.Descriptor.ID) > 0 then
      device:send(clusters.Descriptor.attributes.TagList:read(device, closure_control_eps[1]))
    else
      log.warn("Descriptor cluster not implemented on ClosureControl endpoint, cannot read TagList to determine closure type")
      device:set_field(CLOSURE_TAG, closure_tag_list.NA, {persist = true})
    end
    local battery_feature_eps = device:get_endpoints(
      clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
    )
    if #battery_feature_eps > 0 then
      device:send(clusters.PowerSource.attributes.AttributeList:read(device, battery_feature_eps[1]))
    else
      device:set_field(CLOSURE_BATTERY_SUPPORT, battery_support.NO_BATTERY, {persist = true})
    end
  else -- #device:get_endpoints(clusters.WindowCovering.ID) > 0
    local battery_feature_eps = device:get_endpoints(
      clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
    )
    if #battery_feature_eps > 0 then
      local attribute_list_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
      attribute_list_read:merge(clusters.PowerSource.attributes.AttributeList:read())
      device:send(attribute_list_read)
    else
      match_profile(device, battery_support.NO_BATTERY)
    end
  end
end

local function info_changed(driver, device, event, args)
  local is_window_covering = #device:get_endpoints(clusters.WindowCovering.ID) > 0
  local is_closure = #device:get_endpoints(clusters.ClosureControl.ID) > 0
  if (is_window_covering and device.profile.id ~= args.old_st_store.profile.id) or
    (is_closure and not deep_equals(device.profile, args.old_st_store.profile, { ignore_functions = true })) then
    -- Profile has changed, resubscribe
    device:subscribe()
  elseif args.old_st_store.preferences.reverse ~= device.preferences.reverse then
    if device.preferences.reverse then
      device:set_field(REVERSE_POLARITY, true, { persist = true })
    else
      device:set_field(REVERSE_POLARITY, false, { persist = true })
    end
  elseif is_window_covering then
    -- Something else has changed info (SW update, reinterview, etc.), so
    -- try updating profile as needed
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
  if device:supports_capability_by_id(capabilities.windowShade.ID) then
    device:emit_event(
      capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, {visibility = {displayed = false}})
    )
  end
  device:set_field(REVERSE_POLARITY, false, { persist = true })
end

local function device_removed(driver, device) log.info("device removed") end

-- capability handlers
local function handle_preset(driver, device, cmd)
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
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:set_field(PRESET_LEVEL_KEY, cmd.args.position)
  device:emit_event_for_endpoint(endpoint_id, capabilities.windowShadePreset.position(cmd.args.position))
end

-- close covering
local function handle_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local reverse = device:get_field(REVERSE_POLARITY)
  local req = reverse and clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id) or
    clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
  if #device:get_endpoints(clusters.ClosureControl.ID) > 0 then
    req = reverse and clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN
    ) or clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED
    )
  end
  device:send(req)
end

-- open covering
local function handle_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local reverse = device:get_field(REVERSE_POLARITY)
  local req = reverse and clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id) or
    clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
  if #device:get_endpoints(clusters.ClosureControl.ID) > 0 then
    req = reverse and clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED
    ) or clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN
    )
  end
  device:send(req)
end

-- pause covering
local function handle_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.StopMotion(device, endpoint_id)
  if #device:get_endpoints(clusters.ClosureControl.ID) > 0 then
    req = clusters.ClosureControl.server.commands.Stop(device, endpoint_id)
  end
  device:send(req)
end

-- move to shade level between 0-100
local function handle_shade_level(driver, device, cmd)
  if #device:get_endpoints(clusters.ClosureDimension.ID) > 0 then
    local dim_ep = device:component_to_endpoint(cmd.component)
    if dim_ep then
      device:send(clusters.ClosureDimension.server.commands.SetTarget(device, dim_ep, cmd.args.shadeLevel * 100))
      return
    end
  else
    local endpoint_id = device:component_to_endpoint(cmd.component)
    local hundredths_lift_percentage = (100 - cmd.args.shadeLevel) * 100
    device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(device, endpoint_id, hundredths_lift_percentage))
  end
end

-- move to level between 0-100 (for door/gate/garage-door Closure devices)
local function handle_level(driver, device, cmd)
  local dim_ep = device:component_to_endpoint(cmd.component)
  if #device:get_endpoints(clusters.ClosureDimension.ID) == 0 or not dim_ep then return end
  device:send(clusters.ClosureDimension.server.commands.SetTarget(device, dim_ep, cmd.args.level * 100))
end

-- move to shade tilt level between 0-100
local function handle_shade_tilt_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local tilt_percentage_value = 100 - cmd.args.level
  local hundredths_tilt_percentage = tilt_percentage_value * 100
  local req = clusters.WindowCovering.server.commands.GoToTiltPercentage(
    device, endpoint_id, hundredths_tilt_percentage
  )
  device:send(req)
end

-- current lift/tilt percentage, changed to 100ths percent
local current_pos_handler = function(attribute)
  return function(driver, device, ib, response)
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

-- checks the current position of the shade
local function current_status_handler(driver, device, ib, response)
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
  if ib.data.value ~= nil then
    --TODO should we invert this like we do for CurrentLiftPercentage100ths?
    local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(level))
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
  local is_closure = #device:get_endpoints(clusters.ClosureControl.ID) > 0
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) is present.
    if attr.value == 0x0C then
      if is_closure then
        device:set_field(CLOSURE_BATTERY_SUPPORT, battery_support.BATTERY_PERCENTAGE, {persist = true})
        match_profile_for_closure(device)
      else
        match_profile(device, battery_support.BATTERY_PERCENTAGE)
      end
      return
    elseif attr.value == 0x0E then
      if is_closure then
        device:set_field(CLOSURE_BATTERY_SUPPORT, battery_support.BATTERY_LEVEL, {persist = true})
        match_profile_for_closure(device)
      else
        match_profile(device, battery_support.BATTERY_LEVEL)
      end
      return
    end
  end
end

local function tag_list_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local tag_value
  for _, v in ipairs(ib.data.elements) do
    local tag = v.elements
    if tag and tag.namespace_id and tag.namespace_id.value == 0x44 then
      tag_value = tag.tag and tag.tag.value
      break
    end
  end
  local closure_tags = {
    [0] = closure_tag_list.COVERING,
    [1] = closure_tag_list.WINDOW,
    [2] = closure_tag_list.BARRIER,
    [3] = closure_tag_list.CABINET,
    [4] = closure_tag_list.GATE,
    [5] = closure_tag_list.GARAGE_DOOR,
    [6] = closure_tag_list.DOOR,
  }
  if closure_tags[tag_value] then
    device:set_field(CLOSURE_TAG, closure_tags[tag_value], {persist = true})
  else
    device:set_field(CLOSURE_TAG, closure_tag_list.NA, {persist = true})
  end
  match_profile_for_closure(device)
end

local function closure_dimension_current_state_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  clusters.ClosureDimension.types.DimensionStateStruct:augment_type(ib.data)
  local pos_field = ib.data.elements.position
  if not pos_field or pos_field.value == nil then return end
  local level = math.floor(pos_field.value / 100)
  if device:supports_capability_by_id(capabilities.doorControl.ID) then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.level.level(level))
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(level))
  end
end

local function set_closure_control_state(device, endpoint_id, field)
  local cache = device:get_field(CLOSURE_CONTROL_STATE_CACHE) or {}
  if not cache[endpoint_id] then cache[endpoint_id] = {} end
  for k, v in pairs(field) do
    cache[endpoint_id][k] = v
  end
  device:set_field(CLOSURE_CONTROL_STATE_CACHE, cache)
end

local function emit_closure_control_capability(device, endpoint_id)
  local closure_control_state = device:get_field(CLOSURE_CONTROL_STATE_CACHE)[endpoint_id] or {}
  local reverse = device:get_field(REVERSE_POLARITY)

  local main = closure_control_state.main
  local current = closure_control_state.current
  local target = closure_control_state.target

  local closure_capability = capabilities.windowShade.windowShade
  if device:supports_capability_by_id(capabilities.doorControl.ID) then
    closure_capability = capabilities.doorControl.door
  end

  if main == clusters.ClosureControl.types.MainStateEnum.MOVING then
    if target == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED then
      device:emit_event_for_endpoint(endpoint_id, reverse and closure_capability.opening() or closure_capability.closing())
    elseif target == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN then
      device:emit_event_for_endpoint(endpoint_id, reverse and closure_capability.closing() or closure_capability.opening())
    end
  elseif main == clusters.ClosureControl.types.MainStateEnum.STOPPED or main == nil then
    if current == nil then return end
    if current == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED then
      device:emit_event_for_endpoint(endpoint_id, reverse and closure_capability.open() or closure_capability.closed())
    elseif current == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED or
      device:supports_capability_by_id(capabilities.doorControl.ID) then
      -- doorControl does not support partially open; treat any not- fully closed as open
      device:emit_event_for_endpoint(endpoint_id, reverse and closure_capability.closed() or closure_capability.open())
    else
      device:emit_event_for_endpoint(endpoint_id, closure_capability.partially_open())
    end
  end
end

local function main_state_attr_handler(driver, device, ib, response)
  if ib.data.value == nil then return end
  set_closure_control_state(device, ib.endpoint_id, { main = ib.data.value })
  emit_closure_control_capability(device, ib.endpoint_id)
end

local function overall_current_state_attr_handler(driver, device, ib, response)
  clusters.ClosureControl.types.OverallCurrentStateStruct:augment_type(ib.data)
  for _, v in pairs(ib.data.elements or {}) do
    if v.field_id == 0 then
      local current = v.value
      set_closure_control_state(device, ib.endpoint_id, { current = current })
      emit_closure_control_capability(device, ib.endpoint_id)
      break
    end
  end
end

local function overall_target_state_attr_handler(driver, device, ib, response)
  clusters.ClosureControl.types.OverallTargetStateStruct:augment_type(ib.data)
  for _, v in pairs(ib.data.elements or {}) do
    if v.field_id == 0 then
      local target = v.value
      set_closure_control_state(device, ib.endpoint_id, { target = target })
      emit_closure_control_capability(device, ib.endpoint_id)
      break
    end
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    removed = device_removed,
    added = device_added,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
  matter_handlers = {
    attr = {
      --TODO LevelControl may not be needed for certified devices since
      -- certified should use CurrentPositionLiftPercent100ths attr
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = level_attr_handler,
      },
      [clusters.WindowCovering.ID] = {
        --uses percent100ths more often
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_pos_handler(capabilities.windowShadeLevel.shadeLevel),
        [clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths.ID] = current_pos_handler(capabilities.windowShadeTiltLevel.shadeTiltLevel),
        [clusters.WindowCovering.attributes.OperationalStatus.ID] = current_status_handler,
      },
      [clusters.ClosureControl.ID] = {
        [clusters.ClosureControl.attributes.MainState.ID] = main_state_attr_handler,
        [clusters.ClosureControl.attributes.OverallCurrentState.ID] = overall_current_state_attr_handler,
        [clusters.ClosureControl.attributes.OverallTargetState.ID] = overall_target_state_attr_handler,
      },
      [clusters.ClosureDimension.ID] = {
        [clusters.ClosureDimension.attributes.CurrentState.ID] = closure_dimension_current_state_handler,
      },
      [clusters.Descriptor.ID] = {
        [clusters.Descriptor.attributes.TagList.ID] = tag_list_handler,
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
      clusters.WindowCovering.attributes.OperationalStatus,
      clusters.ClosureControl.attributes.MainState,
      clusters.ClosureControl.attributes.OverallCurrentState,
      clusters.ClosureControl.attributes.OverallTargetState,
    },
    [capabilities.doorControl.ID] = {
      clusters.ClosureControl.attributes.MainState,
      clusters.ClosureControl.attributes.OverallCurrentState,
      clusters.ClosureControl.attributes.OverallTargetState,
    },
    [capabilities.windowShadeLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths,
      clusters.ClosureDimension.attributes.CurrentState,
    },
    [capabilities.level.ID] = {
      clusters.ClosureDimension.attributes.CurrentState,
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
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.open.NAME] = handle_open,
      [capabilities.doorControl.commands.close.NAME] = handle_close,
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = handle_shade_level,
    },
    [capabilities.level.ID] = {
      [capabilities.level.commands.setLevel.NAME] = handle_level,
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
  sub_drivers = {
    -- for devices sending a position update while device is in motion
    require("matter-window-covering-position-updates-while-moving")
  }
}

local matter_driver = MatterDriver("matter-window-covering", matter_driver_template)
matter_driver:run()
