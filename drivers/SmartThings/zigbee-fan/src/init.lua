-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local device_init = function(self, device)
  local configurationMap = require "configurations"
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local zigbee_fan_driver = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.fanspeed
  },
  sub_drivers = require("sub_drivers"),
  lifecycle_handlers = {
    init = device_init
  },
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_fan_driver,zigbee_fan_driver.supported_capabilities)
local fan = ZigbeeDriver("zigbee-fan", zigbee_fan_driver)
fan:run()
