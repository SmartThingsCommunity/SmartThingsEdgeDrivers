-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"

local IkeaScrollFields = {}

-- PowerSource supported on Root Node
IkeaScrollFields.ENDPOINT_POWER_SOURCE = 0

-- Switch Endpoints used for basic press functionality
IkeaScrollFields.ENDPOINTS_PRESS = {3, 6, 9}

-- Required Events for the ENDPOINTS_PRESS.
IkeaScrollFields.switch_press_subscribed_events = {
  clusters.Switch.events.InitialPress.ID,
  clusters.Switch.events.MultiPressComplete.ID,
  clusters.Switch.events.LongPress.ID,
}

return IkeaScrollFields
