-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"
local generic_event_handlers = require "switch_handlers.event_handlers"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollEventHandlers = {}

local function rotate_amount_event_helper(device, endpoint_id, num_presses_to_handle)
  -- to cut down on checks, we can assume that if the endpoint is not in ENDPOINTS_UP_SCROLL, it is in ENDPOINTS_DOWN_SCROLL
  local scroll_direction = switch_utils.tbl_contains(scroll_fields.ENDPOINTS_UP_SCROLL, endpoint_id) and 1 or -1
  local scroll_amount = st_utils.clamp_value(scroll_direction * scroll_fields.PER_SCROLL_EVENT_ROTATION * num_presses_to_handle, -100, 100)
  device:emit_event_for_endpoint(endpoint_id, capabilities.knob.rotateAmount(scroll_amount, {state_change = true}))
end

-- Used by ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL, not ENDPOINTS_PUSH
function IkeaScrollEventHandlers.multi_press_ongoing_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    -- Ignore MultiPressOngoing events from push endpoints.
    device.log.debug("Received MultiPressOngoing event from push endpoint, ignoring.")
  else
    local cur_num_presses_counted = ib.data and ib.data.elements and ib.data.elements.current_number_of_presses_counted.value or 0
    local num_presses_to_handle = cur_num_presses_counted - (device:get_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED) or 0)
    if num_presses_to_handle > 0 then
      device:set_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED, cur_num_presses_counted)
      rotate_amount_event_helper(device, ib.endpoint_id, num_presses_to_handle)
    end
  end
end

function IkeaScrollEventHandlers.multi_press_complete_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    generic_event_handlers.multi_press_complete_handler(driver, device, ib, response)
  else
    local total_num_presses_counted = ib.data and ib.data.elements and ib.data.elements.total_number_of_presses_counted.value or 0
    local num_presses_to_handle = total_num_presses_counted - (device:get_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED) or 0)
    if num_presses_to_handle > 0 then
      rotate_amount_event_helper(device, ib.endpoint_id, num_presses_to_handle)
    end
    -- reset the LATEST_NUMBER_OF_PRESSES_COUNTED to nil at the end of a MultiPress chain.
    device:set_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED, nil)
  end
end

function IkeaScrollEventHandlers.initial_press_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    generic_event_handlers.initial_press_handler(driver, device, ib, response)
  else
    -- Ignore InitialPress events from non-push endpoints. Presently, we want to solely
    -- rely on MultiPressOngoing events to handle rotation for those endpoints.
    device.log.debug("Received InitialPress event from scroll endpoint, ignoring.")
  end
end

return IkeaScrollEventHandlers
