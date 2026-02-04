-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local closure_fields = require "sub_drivers.closures.closure_utils.fields"

clusters.ClosureControl = require "embedded_clusters.ClosureControl"

local ClosureAttributeHandlers = {}

local function set_closure_control_state(device, endpoint_id, field)
  local cache = device:get_field(closure_fields.CLOSURE_CONTROL_STATE_CACHE) or {}
  if not cache[endpoint_id] then cache[endpoint_id] = {} end
  for k, v in pairs(field) do
    cache[endpoint_id][k] = v
  end
  device:set_field(closure_fields.CLOSURE_CONTROL_STATE_CACHE, cache)
end

local function emit_closure_control_capability(device, endpoint_id)
  local closure_control_state = device:get_field(closure_fields.CLOSURE_CONTROL_STATE_CACHE)[endpoint_id] or {}

  local main = closure_control_state.main
  local current = closure_control_state.current
  local target = closure_control_state.target

  local closure_capability = capabilities.windowShade.windowShade
  if device:supports_capability_by_id(capabilities.doorControl.ID) then
    closure_capability = capabilities.doorControl.door
  end

  if main == clusters.ClosureControl.types.MainStateEnum.MOVING then
    if target == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED then
      device:emit_event_for_endpoint(endpoint_id, closure_capability.closing())
    elseif target == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN then
      device:emit_event_for_endpoint(endpoint_id, closure_capability.opening())
    end
  elseif main == clusters.ClosureControl.types.MainStateEnum.STOPPED or main == nil then
    if current == nil then return end
    if current == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED then
      device:emit_event_for_endpoint(endpoint_id, closure_capability.closed())
    elseif current == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED or
      device:supports_capability_by_id(capabilities.doorControl.ID) then
        -- doorControl does not support partially open; treat any not- fully closed as open
      device:emit_event_for_endpoint(endpoint_id, closure_capability.open())
    else
      device:emit_event_for_endpoint(endpoint_id, closure_capability.partially_open())
    end
  end
end

function ClosureAttributeHandlers.main_state_attr_handler(driver, device, ib, response)
  if ib.data.value == nil then return end
  set_closure_control_state(device, ib.endpoint_id, { main = ib.data.value })
  emit_closure_control_capability(device, ib.endpoint_id)
end

function ClosureAttributeHandlers.overall_current_state_attr_handler(driver, device, ib, response)
  if ib.data.elements == nil or ib.data.elements.position == nil or ib.data.elements.position.value == nil then return end
  local current = ib.data.elements.position.value
  set_closure_control_state(device, ib.endpoint_id, { current = current })
  emit_closure_control_capability(device, ib.endpoint_id)
end

function ClosureAttributeHandlers.overall_target_state_attr_handler(driver, device, ib, response)
  if ib.data.elements == nil or ib.data.elements.position == nil or ib.data.elements.position.value == nil then return end
  local target = ib.data.elements.position.value
  set_closure_control_state(device, ib.endpoint_id, { target = target })
  emit_closure_control_capability(device, ib.endpoint_id)
end

ClosureAttributeHandlers.current_pos_handler = function(attribute)
  return function(driver, device, ib, response)
    if ib.data.value == nil then return end
    local windowShade = capabilities.windowShade.windowShade
    local position = 100 - math.floor(ib.data.value / 100)
    local reverse = device:get_field(closure_fields.REVERSE_POLARITY)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(position))

    if attribute == capabilities.windowShadeLevel.shadeLevel then
      device:set_field(closure_fields.CURRENT_LIFT, position)
    else
      device:set_field(closure_fields.CURRENT_TILT, position)
    end

    local lift_position = device:get_field(closure_fields.CURRENT_LIFT)
    local tilt_position = device:get_field(closure_fields.CURRENT_TILT)

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

function ClosureAttributeHandlers.current_status_handler(driver, device, ib, response)
  local windowShade = capabilities.windowShade.windowShade
  local reverse = device:get_field(closure_fields.REVERSE_POLARITY)
  local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
  if state == 1 then -- opening
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closing() or windowShade.opening())
  elseif state == 2 then -- closing
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.opening() or windowShade.closing())
  elseif state ~= 0 then -- unknown
    device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
  end
end

function ClosureAttributeHandlers.level_attr_handler(driver, device, ib, response)
  if ib.data.value == nil then return end
  local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(level))
end

return ClosureAttributeHandlers
