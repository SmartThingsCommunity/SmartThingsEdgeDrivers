-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local defaults = require "st.zigbee.defaults"
local lazy_load_if_possible = require "lazy_load_subdriver"

local zigbee_air_quality_detector_template = {
  supported_capabilities = {
    capabilities.airQualityHealthConcern,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.carbonDioxideMeasurement,
    capabilities.carbonDioxideHealthConcern,
    capabilities.fineDustSensor,
    capabilities.fineDustHealthConcern,
    capabilities.veryFineDustSensor,
    capabilities.veryFineDustHealthConcern,
    capabilities.dustSensor,
    capabilities.dustHealthConcern,
    capabilities.formaldehydeMeasurement,
    capabilities.tvocMeasurement,
    capabilities.tvocHealthConcern
  },
  sub_drivers = { lazy_load_if_possible("MultiIR") },
}

defaults.register_for_default_handlers(zigbee_air_quality_detector_template, zigbee_air_quality_detector_template.supported_capabilities)
local zigbee_air_quality_detector_driver = ZigbeeDriver("zigbee-air-quality-detector", zigbee_air_quality_detector_template)
zigbee_air_quality_detector_driver:run()
