-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local closure_fields = require "sub_drivers.closures.closure_utils.fields"

clusters.ClosureControl = require "embedded_clusters.ClosureControl"

local ClosureAttributeHandlers = {}

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

function ClosureAttributeHandlers.main_state_attr_handler(driver, device, ib, response)
  if ib.data.value == nil then return end
  local windowShade = capabilities.windowShade.windowShade
  local current_state = device:get_field(closure_fields.CURRENT_STATE) or clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED
  local target_state = device:get_field(closure_fields.TARGET_STATE) or clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED

  if device:supports_capability_by_id(capabilities.windowShade.ID) then
    if ib.data.value == clusters.ClosureControl.types.MainStateEnum.MOVING then
      if target_state == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.closing())
      elseif target_state == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.opening())
      end
    elseif ib.data.value == clusters.ClosureControl.types.MainStateEnum.STOPPED then
      if current_state == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.closed())
      elseif current_state == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.open())
      else -- PARTIALLY_OPENED, OPENED_FOR_PEDESTRIAN, OPENED_FOR_VENTILATION, or OPENED_AT_SIGNATURE
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
      end
    end
  else -- device:supports_capability_by_id(capabilities.doorControl.ID)
    if ib.data.value == clusters.ClosureControl.types.MainStateEnum.MOVING then
      if target_state == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.door.closing())
      elseif target_state == clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.door.opening())
      end
    elseif ib.data.value == clusters.ClosureControl.types.MainStateEnum.STOPPED then
      if current_state == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.door.closed())
      else
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.doorControl.open())
      end
    end
  end
  device:set_field(closure_fields.MAIN_STATE, ib.data.value)
end

function ClosureAttributeHandlers.overall_current_state_attr_handler(driver, device, ib, response)
  if ib.data.elements == nil or ib.data.elements.position.value == nil then return end
  local windowShade = capabilities.windowShade.windowShade
  local main_state = device:get_field(closure_fields.MAIN_STATE) or clusters.ClosureControl.types.MainStateEnum.STOPPED

  if device:supports_capability_by_id(capabilities.windowShade.ID) then
    if main_state == clusters.ClosureControl.types.MainStateEnum.STOPPED then
      if ib.data.elements.position.value == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.closed())
      elseif ib.data.elements.position.value == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.open())
      else -- PARTIALLY_OPENED, OPENED_FOR_PEDESTRIAN, OPENED_FOR_VENTILATION, or OPENED_AT_SIGNATURE
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
      end
    end
  else -- device:supports_capability_by_id(capabilities.doorControl.ID)
    if main_state == clusters.ClosureControl.types.MainStateEnum.STOPPED then
      if ib.data.elements.position.value == clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.door.closed())
      else
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.doorControl.open())
      end
    end
  end
  device:set_field(closure_fields.CURRENT_STATE, ib.data.elements.position.value)
  end

function ClosureAttributeHandlers.overall_target_state_attr_handler(driver, device, ib, response)
  if ib.data.elements == nil or ib.data.elements.position.value == nil then return end
  device:set_field(closure_fields.TARGET_STATE, ib.data.elements.position.value)
end

return ClosureAttributeHandlers
