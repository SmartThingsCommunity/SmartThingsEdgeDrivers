-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"

local IkeaScrollFields = {}

IkeaScrollFields.ENDPOINTS_PRESS = {3, 6, 9}

IkeaScrollFields.switch_press_subscribed_events = {
  clusters.Switch.events.MultiPressComplete.ID,
  clusters.Switch.events.LongPress.ID,
}

return IkeaScrollFields
