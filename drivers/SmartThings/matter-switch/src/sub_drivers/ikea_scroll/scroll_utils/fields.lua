-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"

local IkeaScrollFields = {}

-- PowerSource supported on Root Node
IkeaScrollFields.ENDPOINT_POWER_SOURCE = 0

-- Generic Switch Endpoints used for basic push functionality
IkeaScrollFields.ENDPOINTS_PUSH = {3, 6, 9}

-- Generic Switch Endpoints used for Up Scroll functionality
IkeaScrollFields.ENDPOINTS_UP_SCROLL = {1, 4, 7}

-- Generic Switch Endpoints used for Down Scroll functionality
IkeaScrollFields.ENDPOINTS_DOWN_SCROLL = {2, 5, 8}

-- Amount to rotate per scroll event
-- 6 == st_utils.round(1/18 * 100), where 18 is the maximum number of presses that can be pressed at a time
IkeaScrollFields.PER_SCROLL_EVENT_ROTATION = 6

-- Field to track the latest number of presses handled during a single scroll event sequence
IkeaScrollFields.LATEST_NUMBER_OF_PRESSES_HANDLED = "__latest_number_of_presses_handled"

-- Field to track the global rotate amount state for the device to ensure no scroll events mapped outside of state bounds are emitted
IkeaScrollFields.GLOBAL_ROTATE_AMOUNT_STATE = "__global_rotate_amount_state"

-- Required Events for the ENDPOINTS_PUSH.
IkeaScrollFields.switch_press_subscribed_events = {
  clusters.Switch.events.InitialPress.ID,
  clusters.Switch.events.MultiPressComplete.ID,
  clusters.Switch.events.LongPress.ID,
}

-- Required Events for the ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL. Adds a
-- MultiPressOngoing subscription to handle step functionality in real-time
IkeaScrollFields.switch_scroll_subscribed_events = {
  clusters.Switch.events.InitialPress.ID,
  clusters.Switch.events.MultiPressOngoing.ID,
  clusters.Switch.events.MultiPressComplete.ID,
}

return IkeaScrollFields
