-- Copyright 2024 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local defaults = require "st.zigbee.defaults"

local zigbee_air_quality_detector_template = {
    supported_capabilities = {
      capabilities.temperatureMeasurement,
      capabilities.relativeHumidityMeasurement,
      capabilities.carbonDioxideHealthConcern,
      capabilities.carbonDioxideMeasurement,
      capabilities.fineDustHealthConcern,
      capabilities.fineDustSensor,
      capabilities.veryFineDustHealthConcern,
      capabilities.veryFineDustSensor,
      capabilities.dustHealthConcern,
      capabilities.fineDustSensor,
      capabilities.dustSensor,
      capabilities.formaldehydeMeasurement,
      capabilities.tvocMeasurement
    },
    sub_drivers = { require("maileke") }
}

defaults.register_for_default_handlers(zigbee_air_quality_detector_template, zigbee_air_quality_detector_template.supported_capabilities)
local zigbee_air_quality_detector_driver = ZigbeeDriver("zigbee-air-quality-detector", zigbee_air_quality_detector_template)
zigbee_air_quality_detector_driver:run()