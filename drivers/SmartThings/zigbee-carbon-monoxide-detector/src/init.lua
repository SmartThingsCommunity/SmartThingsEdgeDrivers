-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local defaults = require "st.zigbee.defaults"
local constants = require "st.zigbee.constants"

--Temperature Measurement
local zigbee_carbon_monoxide_driver_template = {
    supported_capabilities = {
        capabilities.carbonMonoxideDetector,
        capabilities.battery,
        capabilities.carbonMonoxideMeasurement,
        capabilities.temperatureMeasurement,
        capabilities.smokeDetector,
        capabilities.tamperAlert,
        capabilities.alarm
    },
    ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
    health_check = false,
    sub_drivers = require("sub_drivers"),
}

defaults.register_for_default_handlers(zigbee_carbon_monoxide_driver_template,
    zigbee_carbon_monoxide_driver_template.supported_capabilities, {native_capability_attrs_enabled = true})
local zigbee_carbon_monoxide_driver = ZigbeeDriver("zigbee-carbon-monoxide-detector", zigbee_carbon_monoxide_driver_template)
zigbee_carbon_monoxide_driver:run()
