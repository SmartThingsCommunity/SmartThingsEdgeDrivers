-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local do_configure = function(self, device)
  device:configure()
  device:refresh()
end

local zigbee_illuminance_driver = {
  supported_capabilities = {
    capabilities.illuminanceMeasurement,
    capabilities.battery
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  sub_drivers = require("sub_drivers"),
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_illuminance_driver, zigbee_illuminance_driver.supported_capabilities)
local driver = ZigbeeDriver("zigbee-illuminance-sensor", zigbee_illuminance_driver)
driver:run()
