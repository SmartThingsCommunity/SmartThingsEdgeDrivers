-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local zigbee_water_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.battery,
    capabilities.hardwareFault,
    capabilities.fanSpeed,
    capabilities.mode
  },
  sub_drivers = require("sub_drivers"),
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_water_driver_template, zigbee_water_driver_template.supported_capabilities)
local driver = ZigbeeDriver("zigbee-watering-kit", zigbee_water_driver_template)
driver:run()
