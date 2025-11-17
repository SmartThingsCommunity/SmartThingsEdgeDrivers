-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"

local zigbee_thing_template = {
  supported_capabilities = {
    capabilities.refresh,
  },
  health_check = false,
}

local zigbee_thing = ZigbeeDriver("zigbee_thing", zigbee_thing_template)
zigbee_thing:run()
