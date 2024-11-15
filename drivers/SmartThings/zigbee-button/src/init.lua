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
local IASZone = (require "st.zigbee.zcl.clusters").IASZone
local TemperatureMeasurement = (require "st.zigbee.zcl.clusters").TemperatureMeasurement

local temperature_measurement_defaults = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

local generate_event_from_zone_status = function(driver, device, zone_status, zb_rx)
  local event
  local additional_fields = {
    state_change = true
  }
  if zone_status:is_alarm1_set() and zone_status:is_alarm2_set() then
    event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_alarm1_set() then
    event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_alarm2_set() then
    event = capabilities.button.button.double(additional_fields)
  end
  if event ~= nil then
    device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      event)
    if device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value) ~= "main" then
      device:emit_event(event)
    end
  end
end

--- Default handler for zoneStatus attribute on the IAS Zone cluster
---
--- This converts the 2 byte bitmap value to motionSensor.motion."active" or motionSensor.motion."inactive"
---
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param zone_status 2 byte bitmap zoneStatus attribute value of the IAS Zone cluster
--- @param zb_rx ZigbeeMessageRx the full message this report came in

local ias_zone_status_attr_handler = function(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

--- Default handler for zoneStatus change handler
---
--- This converts the 2 byte bitmap value to motionSensor.motion."active" or motionSensor.motion."inactive"
---
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param zb_rx containing zoneStatus attribute value of the IAS Zone cluster

local ias_zone_status_change_handler = function(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

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

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed","held","double"}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
  device:send(TemperatureMeasurement.attributes.MaxMeasuredValue:read(device))
  device:send(TemperatureMeasurement.attributes.MinMeasuredValue:read(device))
end

local zigbee_button_driver_template = {
  supported_capabilities = {
    capabilities.button,
    capabilities.battery,
    capabilities.temperatureMeasurement
  },
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      },
      [TemperatureMeasurement.ID] = {
        [TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MIN_TEMP),
        [TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MAX_TEMP),
      }
    },
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    }
  },
  sub_drivers = {
    require("aqara"),
    require("pushButton"),
    require("frient"),
    require("zigbee-multi-button"),
    require("dimming-remote"),
    require("iris"),
    require("samjin"),
    require("ewelink"),
    require("thirdreality")
  },
  lifecycle_handlers = {
    added = added_handler,
  },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE
}

defaults.register_for_default_handlers(zigbee_button_driver_template, zigbee_button_driver_template.supported_capabilities)
local zigbee_button = ZigbeeDriver("zigbee_button", zigbee_button_driver_template)
zigbee_button:run()
