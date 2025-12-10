-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollEventHandlers = {}

local function rotate_amount_event_helper(device, endpoint_id)
  -- to cut down on checks, we can assume that if the endpoint is not in ENDPOINTS_UP_SCROLL, it is in ENDPOINTS_DOWN_SCROLL
  local scroll_direction = switch_utils.tbl_contains(scroll_fields.ENDPOINTS_UP_SCROLL, endpoint_id) and 1 or -1
  local scroll_amount = scroll_direction * scroll_fields.PER_SCROLL_EVENT_ROTATION
  device:emit_event_for_endpoint(endpoint_id, capabilities.knob.rotateAmount(scroll_amount, {state_change = true}))
end

-- Used by ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL, not ENDPOINTS_PUSH. ENDPOINTS_PUSH use the generic handler
function IkeaScrollEventHandlers.initial_press_handler(driver, device, ib, response)
  rotate_amount_event_helper(device, ib.endpoint_id)
end

-- Used by ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL, not ENDPOINTS_PUSH
function IkeaScrollEventHandlers.multi_press_ongoing_handler(driver, device, ib, response)
  rotate_amount_event_helper(device, ib.endpoint_id)
end

return IkeaScrollEventHandlers
