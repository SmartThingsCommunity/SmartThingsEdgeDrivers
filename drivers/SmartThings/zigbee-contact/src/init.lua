-- Copyright 2022 SmartThings
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

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local constants = require "st.zigbee.constants"
local defaults = require "st.zigbee.defaults"
local configurationMap = require "configurations"
local SMARTSENSE_MULTI_SENSOR_CUSTOM_PROFILE = 0xFC01

local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local zigbee_contact_driver_template = {
  supported_capabilities = {
    capabilities.contactSensor,
    capabilities.temperatureMeasurement,
    capabilities.battery,
    capabilities.threeAxis,
    capabilities.accelerationSensor
  },
  additional_zcl_profiles = {
    [SMARTSENSE_MULTI_SENSOR_CUSTOM_PROFILE] = true
  },
  lifecycle_handlers = {
    init = device_init
  },
  sub_drivers = {
    require("aqara"),
    require("aurora-contact-sensor"),
    require("contact-temperature-sensor"),
    require("multi-sensor"),
    require("smartsense-multi"),
    require("sengled")
  },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE
}

defaults.register_for_default_handlers(zigbee_contact_driver_template, zigbee_contact_driver_template.supported_capabilities)
local zigbee_contact = ZigbeeDriver("zigbee_contact", zigbee_contact_driver_template)
zigbee_contact:run()
