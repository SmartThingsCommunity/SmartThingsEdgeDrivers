-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local fields = {}

fields.REVERSE_POLARITY = "__reverse_polarity"
fields.PRESET_LEVEL_KEY = "__preset_level_key"
fields.DEFAULT_PRESET_LEVEL = 50

fields.battery_support = {
  NO_BATTERY         = "NO_BATTERY",
  BATTERY_LEVEL      = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE",
}

fields.CLOSURE_CONTROL_STATE_CACHE = "__closure_control_state_cache"
fields.CLOSURE_BATTERY_SUPPORT     = "__closure_battery_support"
fields.CLOSURE_TAG                 = "__closure_tag"

fields.closure_tag_list = {
  NA          = "N/A",
  COVERING    = "COVERING",
  WINDOW      = "WINDOW",
  BARRIER     = "BARRIER",
  CABINET     = "CABINET",
  GATE        = "GATE",
  GARAGE_DOOR = "GARAGE_DOOR",
  DOOR        = "DOOR",
}

-- The maximum number of supported panels for a closure device. Note that this is an
-- arbitrary number and should be raised if needed by a closure device with more panels.
fields.MAX_CLOSURE_PANELS = 4

fields.SUBSCRIBED_ATTRIBUTES_KEY = "__subscribed_attributes"

return fields
