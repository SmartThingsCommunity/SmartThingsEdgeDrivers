-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"
local generic_event_handlers = require "switch_handlers.event_handlers"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"
local event_utils = require "sub_drivers.ikea_scroll.scroll_utils.event_utils"

local IkeaScrollEventHandlers = {}

local function rotate_amount_event_helper(device, endpoint_id, num_presses_to_handle)
  if num_presses_to_handle <= 0 then return end

  -- to cut down on checks, we can assume that if the endpoint is not in ENDPOINTS_UP_SCROLL, it is in ENDPOINTS_DOWN_SCROLL
  local scroll_direction = switch_utils.tbl_contains(scroll_fields.ENDPOINTS_UP_SCROLL, endpoint_id) and 1 or -1
  local scroll_amount = st_utils.clamp_value(scroll_direction * scroll_fields.PER_SCROLL_EVENT_ROTATION * num_presses_to_handle, -100, 100)

  if event_utils.is_valid_scroll_amount(device, scroll_amount) then
    device:emit_event_for_endpoint(endpoint_id, capabilities.knob.rotateAmount(scroll_amount, {state_change = true}))
  end
end

-- Used by ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL, not ENDPOINTS_PUSH
function IkeaScrollEventHandlers.multi_press_ongoing_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    device.log.debug("Received MultiPressOngoing event from push endpoint, ignoring.")
  else
    local cur_num_presses_counted = ib.data.elements and ib.data.elements.current_number_of_presses_counted.value or 0
    local cur_multi_press_count = cur_num_presses_counted
    if #response.info_blocks > 1 then
      -- note: keep in mind that response blocks with mutliple info blocks are not supported by unit tests today.
      if event_utils.is_last_valid_info_block(ib.event_id, cur_num_presses_counted, response.info_blocks) then
        local aggregated_presses = event_utils.aggregate_scroll_amount_for_info_blocks(device, response.info_blocks) or {}
        cur_num_presses_counted = aggregated_presses.total_presses or 0
        cur_multi_press_count = aggregated_presses.presses_in_current_chain or 0
      else
        device.log.debug("Received MultiPressOngoing event that is not the last valid info block, ignoring.")
        return
      end
    end
    local num_presses_to_handle = cur_num_presses_counted - (device:get_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_HANDLED) or 0)
    device:set_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_HANDLED, cur_multi_press_count)
    rotate_amount_event_helper(device, ib.endpoint_id, num_presses_to_handle)
  end
end

function IkeaScrollEventHandlers.multi_press_complete_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    generic_event_handlers.multi_press_complete_handler(driver, device, ib, response)
  else
    local total_num_presses_counted = ib.data.elements and ib.data.elements.total_number_of_presses_counted.value or 0
    if #response.info_blocks > 1 then
      -- note: keep in mind that response blocks with mutliple info blocks are not supported by unit tests today.
      if event_utils.is_last_valid_info_block(ib.event_id, total_num_presses_counted, response.info_blocks) then
        local aggregated_presses = event_utils.aggregate_scroll_amount_for_info_blocks(device, response.info_blocks) or {}
        total_num_presses_counted = aggregated_presses.total_presses or 0
      else
        device.log.debug("Received MultiPressComplete event that is not the last valid info block, ignoring.")
        return
      end
    end
    local num_presses_to_handle = total_num_presses_counted - (device:get_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_HANDLED) or 0)
    rotate_amount_event_helper(device, ib.endpoint_id, num_presses_to_handle)
    -- always reset the LATEST_NUMBER_OF_PRESSES_HANDLED to nil at the end of a handled MultiPress chain.
    device:set_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_HANDLED, nil)
  end
end

function IkeaScrollEventHandlers.initial_press_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    generic_event_handlers.initial_press_handler(driver, device, ib, response)
  else
    device.log.debug("Received InitialPress event from scroll endpoint, ignoring.")
  end
end

return IkeaScrollEventHandlers
