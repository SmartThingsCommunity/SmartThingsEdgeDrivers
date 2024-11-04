-- Copyright 2023 SmartThings
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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local device_lib = require "st.device"

local DEFAULT_LEVEL = 0
local STATE_MACHINE = "__state_machine"

local StateMachineEnum = {
  STATE_IDLE = 0x00,
  STATE_MOVING = 0x01,
  STATE_OPERATIONAL_STATE_FIRED = 0x02,
  STATE_CURRENT_POSITION_FIRED = 0x03
}

local SUB_WINDOW_COVERING_VID_PID = {
  {0x10e1, 0x1005} -- VDA
}

local function is_matter_window_covering_position_updates_while_moving(opts, driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    return false
  end
  for i, v in ipairs(SUB_WINDOW_COVERING_VID_PID) do
    if device.manufacturer_info.vendor_id == v[1] and
       device.manufacturer_info.product_id == v[2] then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  device:subscribe()
end

-- current lift percentage, changed to 100ths percent
local function current_pos_handler(driver, device, ib, response)
  local position = 0
  if ib.data.value ~= nil then
    position = 100 - math.floor((ib.data.value / 100))
    device:emit_event_for_endpoint(
      ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(position)
    )
  end
  local state_machine = device:get_field(STATE_MACHINE)
  -- When stat_machine is STATE_IDLE or STATE_CURRENT_POSITION_FIRED, nothing to do
  if state_machine == StateMachineEnum.STATE_MOVING then
    device:set_field(STATE_MACHINE, StateMachineEnum.STATE_CURRENT_POSITION_FIRED)
  elseif state_machine == StateMachineEnum.STATE_OPERATIONAL_STATE_FIRED or state_machine == nil then
    if position == 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.closed())
    elseif position == 100 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.open())
    elseif position > 0 and position < 100 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.partially_open())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.unknown())
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
      position = 100 - math.floor((rb.info_block.data.value / 100))
    end
  end
  local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL --Could use LIFT instead
  local state_machine = device:get_field(STATE_MACHINE)
  -- When stat_machine is STATE_OPERATIONAL_STATE_FIRED, nothing to do
  if state_machine == StateMachineEnum.STATE_IDLE then
    if state == 1 then -- opening
      device:emit_event_for_endpoint(ib.endpoint_id, attr.opening())
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_MOVING)
    elseif state == 2 then -- closing
      device:emit_event_for_endpoint(ib.endpoint_id, attr.closing())
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_MOVING)
    end
  elseif state_machine == StateMachineEnum.STATE_MOVING then
    if state == 0 then -- not moving
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_OPERATIONAL_STATE_FIRED)
    elseif state == 1 then -- opening
      device:emit_event_for_endpoint(ib.endpoint_id, attr.opening())
    elseif state == 2 then -- closing
      device:emit_event_for_endpoint(ib.endpoint_id, attr.closing())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, attr.unknown())
      device:set_field(STATE_MACHINE, StateMachineEnum.STATE_IDLE)
    end
  elseif state_machine == StateMachineEnum.STATE_CURRENT_POSITION_FIRED then
    if state == 0 then -- not moving
      if position == 100 then -- open
        device:emit_event_for_endpoint(ib.endpoint_id, attr.open())
      elseif position == 0 then -- closed
        device:emit_event_for_endpoint(ib.endpoint_id, attr.closed())
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
  can_handle = is_matter_window_covering_position_updates_while_moving,
}

return matter_window_covering_position_updates_while_moving_handler
