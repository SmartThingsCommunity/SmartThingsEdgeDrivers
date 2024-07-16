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
local TemperatureMeasurement = (require "st.zigbee.zcl.clusters").TemperatureMeasurement
local configurationMap = require "configurations"
local SMARTSENSE_MULTI_SENSOR_CUSTOM_PROFILE = 0xFC01

local temperature_measurement_defaults = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

--- Default handler for Temperature min and max measured value on the Temperature measurement cluster
---
--- This starts initially by performing the same conversion in the temperature_measurement_attr_handler function.
--- It then sets the field of whichever measured value is defined by the @param and checks if the fields
--- correctly compare
---
--- @param minOrMax string the string that determines which attribute to set
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param value Int16 the value of the measured temperature
--- @param zb_rx containing the full message this report came in

local temperature_measurement_min_max_attr_handler = function(minOrMax)
  return function(driver, device, value, zb_rx)
    local raw_temp = value.value
    local celc_temp = raw_temp / 100.0
    local temp_scale = "C"

    device:set_field(string.format("%s", minOrMax), celc_temp)

    local min = device:get_field(temperature_measurement_defaults.MIN_TEMP)
    local max = device:get_field(temperature_measurement_defaults.MAX_TEMP)

    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = temp_scale }))
        device:set_field(temperature_measurement_defaults.MIN_TEMP, nil)
        device:set_field(temperature_measurement_defaults.MAX_TEMP, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end

local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local function added_handler(driver, device)
  device:send(TemperatureMeasurement.attributes.MaxMeasuredValue:read(device))
  device:send(TemperatureMeasurement.attributes.MinMeasuredValue:read(device))
end

local zigbee_contact_driver_template = {
  supported_capabilities = {
    capabilities.contactSensor,
    capabilities.temperatureMeasurement,
    capabilities.battery,
    capabilities.threeAxis,
    capabilities.accelerationSensor
  },
  zigbee_handlers = {
    attr = {
      [TemperatureMeasurement.ID] = {
        [TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MIN_TEMP),
        [TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MAX_TEMP),
      }
    }
  },
  additional_zcl_profiles = {
    [SMARTSENSE_MULTI_SENSOR_CUSTOM_PROFILE] = true
  },
  lifecycle_handlers = {
    init = device_init,
    added = added_handler,
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
