-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local DEFAULT_LEVEL = 0
local STATE_MACHINE = "__state_machine"
local REVERSE_POLARITY = "__reverse_polarity"

local StateMachineEnum = {
  STATE_IDLE = 0x00,
  STATE_MOVING = 0x01,
  STATE_OPERATIONAL_STATE_FIRED = 0x02,
  STATE_CURRENT_POSITION_FIRED = 0x03
}



local function device_init(driver, device)
  device:subscribe()
end

-- current lift percentage, changed to 100ths percent
local function current_pos_handler(driver, device, ib, response)
  if ib.data.value == nil then
    return
  end
  local position = 100 - math.floor(ib.data.value / 100)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(position))
  local windowShade = capabilities.windowShade.windowShade
  local reverse = device:get_field(REVERSE_POLARITY)
  local state_machine = device:get_field(STATE_MACHINE)
  -- When state_machine is STATE_IDLE or STATE_CURRENT_POSITION_FIRED, nothing to do
  if state_machine == StateMachineEnum.STATE_MOVING then
    device:set_field(STATE_MACHINE, StateMachineEnum.STATE_CURRENT_POSITION_FIRED)
  elseif state_machine == StateMachineEnum.STATE_OPERATIONAL_STATE_FIRED or state_machine == nil then
    if position == 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
    elseif position == 100 then
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())
    elseif position > 0 and position < 100 then
      device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
    end
    device:set_field(STATE_MACHINE, StateMachineEnum.STATE_IDLE)
  end
end

-- checks the current position of the shade
local function current_status_handler(driver, device, ib, response)
  local attr = capabilities.windowShade.windowShade
  local position = device:get_latest_state(
                     "main", capabilities.windowShadeLevel.ID,
                       capabilities.windowShadeLevel.shadeLevel.NAME
                   ) or DEFAULT_LEVEL
  for _, rb in ipairs(response.info_blocks) do
    if rb.info_block.attribute_id == clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID and
       rb.info_block.cluster_id == clusters.WindowCovering.ID and
       rb.info_block.data ~= nil and
       rb.info_block.data.value ~= nil then
      position = math.floor(rb.info_block.data.value / 100)
    end
  end
  position = 100 - position
  local reverse = device:get_field(REVERSE_POLARITY)
  local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
  local state_machine = device:get_field(STATE_MACHINE)
  -- When state_machine is STATE_OPERATIONAL_STATE_FIRED, nothing to do
  if state_machine == StateMachineEnum.STATE_IDLE then
    if state == 1 then -- opening
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and attr.closing() or attr.opening())
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_MOVING)
    elseif state == 2 then -- closing
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and attr.opening() or attr.closing())
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_MOVING)
    end
  elseif state_machine == StateMachineEnum.STATE_MOVING then
    if state == 0 then -- not moving
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_OPERATIONAL_STATE_FIRED)
    elseif state == 1 then -- opening
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and attr.closing() or attr.opening())
    elseif state == 2 then -- closing
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and attr.opening() or attr.closing())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, attr.unknown())
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_IDLE)
    end
  elseif state_machine == StateMachineEnum.STATE_CURRENT_POSITION_FIRED then
    if state == 0 then -- not moving
      if position == 100 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and attr.closed() or attr.open())
      elseif position == 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and attr.open() or attr.closed())
      else
        device:emit_event_for_endpoint(ib.endpoint_id, attr.partially_open())
      end
    else
      device:emit_event_for_endpoint(ib.endpoint_id, attr.unknown())
    end
    device:set_field(STATE_MACHINE, StateMachineEnum.STATE_IDLE)
  end
end

local matter_window_covering_position_updates_while_moving_handler = {
  NAME = "matter-window-covering-position-updates-while-moving",
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.WindowCovering.ID] = {
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_pos_handler,
        [clusters.WindowCovering.attributes.OperationalStatus.ID] = current_status_handler,
      }
    }
  },
  capability_handlers = {
  },
  can_handle = require("matter-window-covering-position-updates-while-moving.can_handle"),
}

return matter_window_covering_position_updates_while_moving_handler
