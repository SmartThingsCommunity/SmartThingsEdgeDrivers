-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local zigbee_keypad_driver = {
  supported_capabilities = {
    capabilities.securitySystem,
    capabilities.battery,
    capabilities.refresh,
    capabilities.tamperAlert,
    capabilities.lockCodes,
    capabilities.mode,
  },
  sub_drivers = require("sub_drivers"),
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_keypad_driver, zigbee_keypad_driver.supported_capabilities)
local keypad = ZigbeeDriver("zigbee-keypad", zigbee_keypad_driver)
keypad:run()
