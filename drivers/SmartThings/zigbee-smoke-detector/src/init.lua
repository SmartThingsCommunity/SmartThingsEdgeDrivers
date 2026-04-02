-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local constants = require "st.zigbee.constants"

local zigbee_smoke_driver_template = {
  supported_capabilities = {
    capabilities.smokeDetector,
    capabilities.battery,
    capabilities.alarm,
    capabilities.temperatureMeasurement,
    capabilities.temperatureAlarm
  },
  sub_drivers = require("sub_drivers"),
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_smoke_driver_template,
  zigbee_smoke_driver_template.supported_capabilities, {native_capability_attrs_enabled = true})
local zigbee_smoke_driver = ZigbeeDriver("zigbee-smoke-detector", zigbee_smoke_driver_template)
zigbee_smoke_driver:run()
