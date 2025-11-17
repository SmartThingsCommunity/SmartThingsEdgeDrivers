-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local zigbee_illuminance_driver = {
  supported_capabilities = {
    capabilities.illuminanceMeasurement,
    capabilities.battery
  },
  sub_drivers = require("sub_drivers"),
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_illuminance_driver, zigbee_illuminance_driver.supported_capabilities)
local driver = ZigbeeDriver("zigbee-illuminance-sensor", zigbee_illuminance_driver)
driver:run()
