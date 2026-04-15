-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zigbee_constants = require "st.zigbee.constants"

local function device_init(driver, device)
  if device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) == nil then
    device:set_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY, 1, {persist = true})
  end
  if device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) == nil then
    device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 100, {persist = true})
  end
end

local simple_metering_config_subdriver = {
  NAME = "Simple Metering Config",
  supported_capabilities = {
    capabilities.energyMeter,
    capabilities.powerMeter
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = require("simple-metering-config.can_handle")
}

return simple_metering_config_subdriver
