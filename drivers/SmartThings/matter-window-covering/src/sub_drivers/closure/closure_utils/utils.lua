-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local log = require "log"
local version = require "version"

if version.api < 20 then
  clusters.ClosureControl = require "embedded_clusters.ClosureControl"
  clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"
end

local fields = require "sub_drivers.closure.closure_utils.fields"

local utils = {}

function utils.find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then -- 0 is the Matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format(
    "Did not find default endpoint, will use endpoint %d instead",
    device.MATTER_DEFAULT_ENDPOINT
  ))
  return res
end

function utils.get_closure_dimension_eps(device)
  local eps = device:get_endpoints(clusters.ClosureDimension.ID) or {}
  table.sort(eps)
  local result = {}
  for _, ep in ipairs(eps) do
    if ep ~= 0 then
      table.insert(result, ep)
      if #result >= fields.MAX_CLOSURE_PANELS then break end
    end
  end
  return result
end

--- Single-panel devices always map to "main";
--- multi-panel devices map to "windowShade1"..."windowShade4" or "door1"..."door4".
function utils.endpoint_to_component(device, ep_id)
  local dim_eps = utils.get_closure_dimension_eps(device)
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

function utils.component_to_endpoint(device, component_name)
  local dim_eps = utils.get_closure_dimension_eps(device)
  if #dim_eps > 1 then
    local comp_num = tonumber(component_name:match("(%d+)$"))
    if comp_num and dim_eps[comp_num] then
      return dim_eps[comp_num]
    end
  end
  return utils.find_default_endpoint(device, clusters.ClosureControl.ID)
end

function utils.match_profile(device)
  if not device:get_field(fields.CLOSURE_TAG) or not device:get_field(fields.CLOSURE_BATTERY_SUPPORT) then
    log.warn("Closure tag or battery support not set yet, cannot match profile")
    return
  end

  local tag = device:get_field(fields.CLOSURE_TAG)
  local profile_name
  local is_door_type = true

  if tag == fields.closure_tag_list.GATE then
    profile_name = "gate"
  elseif tag == fields.closure_tag_list.GARAGE_DOOR then
    profile_name = "garage-door"
  elseif tag == fields.closure_tag_list.DOOR then
    profile_name = "door"
  else
    -- COVERING, WINDOW, BARRIER, CABINET, NA -> generic covering profile
    profile_name = "covering"
    is_door_type = false
  end

  local optional_caps = {}
  local main_component_capabilities = {}

  local closure_battery = device:get_field(fields.CLOSURE_BATTERY_SUPPORT)
  if closure_battery == fields.battery_support.BATTERY_PERCENTAGE then
    table.insert(main_component_capabilities, capabilities.battery.ID)
  elseif closure_battery == fields.battery_support.BATTERY_LEVEL then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  end

  -- ClosureDimension capabilities: windowShadeLevel (covering) or level (door types)
  local dim_eps = utils.get_closure_dimension_eps(device)
  if #dim_eps > 0 then
    local dim_cap = is_door_type and capabilities.level.ID or capabilities.windowShadeLevel.ID
    if #dim_eps == 1 then
      -- Single ClosureDimension: enable the capability on the main component.
      table.insert(main_component_capabilities, dim_cap)
    else
      -- Multiple ClosureDimensions: one optional component+capability per panel.
      local prefix = is_door_type and "door" or "windowShade"
      for i = 1, math.min(#dim_eps, fields.MAX_CLOSURE_PANELS) do
        table.insert(optional_caps, {prefix .. i, {dim_cap}})
      end
    end
  end

  if #main_component_capabilities > 0 then
    table.insert(optional_caps, 1, {"main", main_component_capabilities})
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
--- @param opts table|nil  { ignore_functions = boolean, ignore_cycles = boolean }
--- @param seen table|nil
--- @return boolean
function utils.deep_equals(a, b, opts, seen)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) == "function" and opts and opts.ignore_functions then return true end
  if type(a) ~= "table" then return false end

  if not (opts and opts.ignore_cycles) then
    seen = seen or {}
    seen[a] = seen[a] or {}
    if seen[a][b] then
      return seen[a][b]
    end
    seen[a][b] = true
  end

  for k, v in pairs(a) do
    if not utils.deep_equals(v, b[k], opts, seen) then
      return false
    end
  end

  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end

  local mt_a = getmetatable(a)
  local mt_b = getmetatable(b)
  return utils.deep_equals(mt_a, mt_b, opts, seen)
end

function utils.set_closure_control_state(device, endpoint_id, field)
  local cache = device:get_field(fields.CLOSURE_CONTROL_STATE_CACHE) or {}
  if not cache[endpoint_id] then cache[endpoint_id] = {} end
  for k, v in pairs(field) do
    cache[endpoint_id][k] = v
  end
  device:set_field(fields.CLOSURE_CONTROL_STATE_CACHE, cache)
end

--- Emits the appropriate windowShade / doorControl capability event from the
--- cached MainState, OverallCurrentState.position, and OverallTargetState.position.
function utils.emit_closure_control_capability(device, endpoint_id)
  local cache = device:get_field(fields.CLOSURE_CONTROL_STATE_CACHE)
  if not cache then return end
  local closure_control_state = cache[endpoint_id] or {}
  local reverse = device:get_field(fields.REVERSE_POLARITY)

  local main    = closure_control_state.main
  local current = closure_control_state.current
  local target  = closure_control_state.target

  local closure_capability = capabilities.windowShade.windowShade
  if device:supports_capability_by_id(capabilities.doorControl.ID) then
    closure_capability = capabilities.doorControl.door
  end

  if main == clusters.ClosureControl.types.MainStateEnum.MOVING then
    if target == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED then
      device:emit_event_for_endpoint(
        endpoint_id, reverse and closure_capability.opening() or closure_capability.closing()
      )
    elseif target == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN then
      device:emit_event_for_endpoint(
        endpoint_id, reverse and closure_capability.closing() or closure_capability.opening()
      )
    end
  elseif main == clusters.ClosureControl.types.MainStateEnum.STOPPED or main == nil then
    if current == nil then return end
    if current == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED then
      device:emit_event_for_endpoint(
        endpoint_id, reverse and closure_capability.open() or closure_capability.closed()
      )
    elseif current == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED or
      device:supports_capability_by_id(capabilities.doorControl.ID) then
      -- doorControl does not support partially_open; treat any non-fully-closed as open
      device:emit_event_for_endpoint(
        endpoint_id, reverse and closure_capability.closed() or closure_capability.open()
      )
    else
      device:emit_event_for_endpoint(endpoint_id, closure_capability.partially_open())
    end
  end
end

--- helper for the switch subscribe override, which adds to a subscribed request for a checked device
---
--- @param checked_device any a Matter device object, either a parent or child device, so not necessarily the same as device
--- @param subscribe_request table a subscribe request that will be appended to as needed for the device
--- @param capabilities_seen table a list of capabilities that have already been checked by previously handled devices
--- @param attributes_seen table a list of attributes that have already been checked
--- @param subscribed_attributes table key-value pairs mapping capability ids to subscribed attributes
function utils.populate_subscribe_request_for_device(checked_device, subscribe_request, capabilities_seen, attributes_seen, subscribed_attributes)
 for _, component in pairs(checked_device.st_store.profile.components) do
    for _, capability in pairs(component.capabilities) do
      if not capabilities_seen[capability.id] then
        for _, attr in ipairs(subscribed_attributes[capability.id] or {}) do
          local cluster_id = attr.cluster or attr._cluster.ID
          local attr_id = attr.ID or attr.attribute
          if not attributes_seen[cluster_id] or not attributes_seen[cluster_id][attr_id] then
            local ib = im.InteractionInfoBlock(nil, cluster_id, attr_id)
            subscribe_request:with_info_block(ib)
            attributes_seen[cluster_id] = attributes_seen[cluster_id] or {}
            attributes_seen[cluster_id][attr_id] = ib
          end
        end
        capabilities_seen[capability.id] = true -- only loop through any capability once
      end
    end
  end
end

function utils.subscribe(device)
  local closure_subscribed_attributes = {
    [capabilities.windowShade.ID] = {
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
      clusters.ClosureDimension.attributes.CurrentState,
    },
    [capabilities.level.ID] = {
      clusters.ClosureDimension.attributes.CurrentState,
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining,
    },
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel,
    },
  }

  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  local capabilities_seen, attributes_seen = {}, {}
  local additional_attributes = {}

  -- The refresh capability command handler in the lua libs uses this key to determine which attributes to read.
  device:set_field(fields.SUBSCRIBED_ATTRIBUTES_KEY, attributes_seen)

  -- If the type of battery support has not yet been determined, add the PowerSource AttributeList to the list of
  -- subscribed attributes in order to determine which if any battery capability should be used.
  if device:get_field(fields.CLOSURE_BATTERY_SUPPORT) == nil then
    local ib = im.InteractionInfoBlock(nil, clusters.PowerSource.ID, clusters.PowerSource.attributes.AttributeList.ID)
    subscribe_request:with_info_block(ib)
  end

  if device:get_field(fields.CLOSURE_TAG) == nil then
    table.insert(additional_attributes, clusters.Descriptor.attributes.TagList)
  end

  utils.populate_subscribe_request_for_device(
    device, subscribe_request, capabilities_seen, attributes_seen, closure_subscribed_attributes
  )

  for _, attr in ipairs(additional_attributes) do
    local cluster_id = attr.cluster or attr._cluster.ID
    local attr_id = attr.ID or attr.attribute
    if not attributes_seen[cluster_id] or not attributes_seen[cluster_id][attr_id] then
      local ib = im.InteractionInfoBlock(nil, cluster_id, attr_id)
      subscribe_request:with_info_block(ib)
      attributes_seen[cluster_id] = attributes_seen[cluster_id] or {}
      attributes_seen[cluster_id][attr_id] = ib
    end
  end

  if #subscribe_request.info_blocks > 0 then
    device:send(subscribe_request)
  end
end

return utils
