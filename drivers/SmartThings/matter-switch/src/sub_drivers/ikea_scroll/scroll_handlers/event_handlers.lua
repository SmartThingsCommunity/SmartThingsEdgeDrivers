-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"
-- local generic_event_handlers = require "switch_handlers.event_handlers"

local IkeaScrollEventHandlers = {}

local function rotate_amount_event_helper(device, endpoint_id)
  -- to cut down on checks, assume that if the endpoint is not in ENDPOINTS_UP_SCROLL, it is in ENDPOINTS_DOWN_SCROLL
  local scroll_direction = switch_utils.tbl_contains(scroll_fields.ENDPOINTS_UP_SCROLL, endpoint_id) and 1 or -1
  local scroll_amount = scroll_direction * scroll_fields.PER_SCROLL_EVENT_ROTATION
  local knob_latest_state = switch_utils.get_latest_state_for_endpoint(
    device, endpoint_id, capabilities.knob.ID, capabilities.knob.rotateAmount.NAME
  ) or 0
  scroll_amount = scroll_amount - knob_latest_state
  if 100 >= scroll_amount and scroll_amount >= -100 then
    device:emit_event_for_endpoint(endpoint_id, capabilities.knob.rotateAmount(scroll_amount))
  end
end

-- Used by ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL, not ENDPOINTS_PUSH
function IkeaScrollEventHandlers.initial_press_handler(driver, device, ib, response)
  rotate_amount_event_helper(device, ib.endpoint_id)
end

-- Used by ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL, not ENDPOINTS_PUSH
function IkeaScrollEventHandlers.multi_press_ongoing_handler(driver, device, ib, response)
  rotate_amount_event_helper(device, ib.endpoint_id)
end

--[[
function IkeaScrollEventHandlers.multi_press_complete_handler(driver, device, ib, response)
  -- use the generic multi_press_complete_handler logic in the case the handled endpoint is an ENDPOINTS_PUSH 
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    generic_event_handlers.multi_press_complete_handler(driver, device, ib, response)
    return
  end
  -- For scroll endpoints (not handled by the above), only use this handler if the total # of push events is 1.
  -- For all cases >1, the event would have already been handled by a MultiPressOngoing event
  local press_value = ib.data and ib.data.elements and ib.data.elements.total_number_of_presses_counted.value or 0
  if press_value == 1 then
    rotate_amount_event_helper(device, ib.endpoint_id)
  end
end
]]

return IkeaScrollEventHandlers
