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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local PowerConfiguration = zcl_clusters.PowerConfiguration
local RelativeHumidity = zcl_clusters.RelativeHumidity
local utils = require "st.utils"

local PLANT_LINK_MANUFACTURER_SPECIFIC_CLUSTER = 0xFC08

local ZIGBEE_HUMIDITY_SENSOR_FINGERPRINTS = {
    { mfr = "", model = "", cluster_id = PLANT_LINK_MANUFACTURER_SPECIFIC_CLUSTER },
    { mfr = "", model = "", cluster_id = zcl_clusters.ElectricalMeasurement.ID }
}

local humidity_value_attr_handler = function(driver, device, value, zb_rx)
  -- adc reading of 0x1ec0 produces a plant fuel level near 0
  -- adc reading of 0x2100 produces a plant fuel level near 100%
  local HUMIDITY_VALUE_MAX = 0x2100
  local HUMIDITY_VALUE_MIN = 0x1EC0
  local humidity_value = value.value
  local percent = ((humidity_value - HUMIDITY_VALUE_MIN) / (HUMIDITY_VALUE_MAX - HUMIDITY_VALUE_MIN)) *100
  percent = utils.clamp_value(percent, 0.0, 100.0)
  device:emit_event(capabilities.relativeHumidityMeasurement.humidity(percent))
end

local battery_mains_voltage_attr_handler = function(driver, device, value, zb_rx)
  local min = 2300
  local percent = (value.value - min) /10
  -- Make sure our percentage is between 0 - 100
  percent = utils.clamp_value(percent, 0.0, 100.0)
  device:emit_event(capabilities.battery.battery(percent))
end

local is_zigbee_plant_link_humidity_sensor = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_HUMIDITY_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model and device:supports_server_cluster(fingerprint.cluster_id) then
      return true
    end
  end

  return false
end

local plant_link_humdity_sensor = {
  NAME = "PlantLink Soil Moisture Sensor",
  supported_capabilities = {
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
  },
  zigbee_handlers = {
    attr = {
      [RelativeHumidity.ID] = {
        [RelativeHumidity.attributes.MeasuredValue.ID] = humidity_value_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.MainsVoltage.ID] = battery_mains_voltage_attr_handler
      }
    }
  },
  can_handle = is_zigbee_plant_link_humidity_sensor
}

return plant_link_humdity_sensor
