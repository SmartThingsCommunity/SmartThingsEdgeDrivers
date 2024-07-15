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
local defaults = require "st.zigbee.defaults"
local constants = require "st.zigbee.constants"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local temperature_measurement_defaults = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

local HAS_RECONFIGURED = "_has_reconfigured"

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

-- TODO: Remove when available in lua libs
-- This is a temporary method to lower battery consumption in several devices.
-- Disparities were noted between DTH implementations and driver defaults. -sg
local do_refresh = function(driver, device, command)
  device:refresh()

  if device:get_field(HAS_RECONFIGURED) == nil then
    if device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) and device:supports_server_cluster(zcl_clusters.TemperatureMeasurement.ID) then
      device:send(zcl_clusters.TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 600, 100))
    end

    if device:supports_capability_by_id(capabilities.motionSensor.ID) and device:supports_server_cluster(zcl_clusters.IASZone.ID) then
      device:send(zcl_clusters.IASZone.attributes.ZoneStatus:configure_reporting(device, 0xFFFF, 0x0000, 0)) -- reset to default
    end
    device:set_field(HAS_RECONFIGURED, true)
  end
end

local added_handler = function(self, device)
  device:send(zcl_clusters.TemperatureMeasurement.attributes.MinMeasuredValue:read(device))
  device:send(zcl_clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:read(device))
end

local zigbee_motion_driver = {
  supported_capabilities = {
    capabilities.motionSensor,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
    capabilities.presenceSensor,
    capabilities.contactSensor
  },
  zigbee_handlers = {
    attr = {
      [zcl_clusters.TemperatureMeasurement.ID] = {
        [zcl_clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MIN_TEMP),
        [zcl_clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MAX_TEMP),
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    added = added_handler
  },
  sub_drivers = {
    require("aqara"),
    require("aurora"),
    require("ikea"),
    require("iris"),
    require("gatorsystem"),
    require("motion_timeout"),
    require("nyce"),
    require("zigbee-plugin-motion-sensor"),
    require("compacta"),
    require("frient"),
    require("samjin"),
    require("battery-voltage"),
    require("centralite"),
    require("smartthings"),
    require("smartsense"),
    require("thirdreality"),
    require("sengled")
  },
  additional_zcl_profiles = {
    [0xFC01] = true
  },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE
}

defaults.register_for_default_handlers(zigbee_motion_driver, zigbee_motion_driver.supported_capabilities)
local motion = ZigbeeDriver("zigbee-motion", zigbee_motion_driver)
motion:run()
