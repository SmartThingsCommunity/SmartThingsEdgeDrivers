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
local clusters = require "st.zigbee.zcl.clusters"
local ApplianceEventsAlerts = clusters.ApplianceEventsAlerts
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local device_management = require "st.zigbee.device_management"

local handle_alerts_notification_payload = function(driver, device, zb_rx)
  local alert_struct = zb_rx.body.zcl_body.alert_structure_list[1]

  if alert_struct:get_alert_id() == 0x81 then
    local is_wet = alert_struct:get_category() == 0x01 and alert_struct:get_presence_recovery() == 0x01
    device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      is_wet and capabilities.waterSensor.water.wet() or capabilities.waterSensor.water.dry())
  end
end

local function added_handler(self, device)
  -- device:emit_event(capabilities.waterSensor.water.dry())
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, ApplianceEventsAlerts.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, TemperatureMeasurement.ID, self.environment_info.hub_zigbee_eui))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 300, 16))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))

  device:refresh()
end

local leaksmart_water_sensor = {
  NAME = "leakSMART Water Leak Sensor",
  lifecycle_handlers = {
    added = added_handler,
    doConfigure = do_configure
  },

  zigbee_handlers = {
    cluster = {
      [ApplianceEventsAlerts.ID] = {
        [ApplianceEventsAlerts.client.commands.AlertsNotification.ID] = handle_alerts_notification_payload,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "WAXMAN" and device:get_model() == "leakSMART Water Sensor V2"
  end
}

return leaksmart_water_sensor
