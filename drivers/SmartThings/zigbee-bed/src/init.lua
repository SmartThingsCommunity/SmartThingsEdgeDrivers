-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local zigbee_bed_template = {
  supported_capabilities = {
    capabilities.refresh,
  },
  sub_drivers = require("sub_drivers"),
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_bed_template, zigbee_bed_template.supported_capabilities)
local zigbee_bed_driver = ZigbeeDriver("zigbee-bed", zigbee_bed_template)
zigbee_bed_driver:run()
