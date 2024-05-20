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

local zcl_commands = require "st.zigbee.zcl.global_commands"
local multi_utils = require "multi-sensor/multi_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local contactSensor_defaults = require "st.zigbee.defaults.contactSensor_defaults"
local capabilities = require "st.capabilities"

local MULTI_SENSOR_FINGERPRINTS = {
  { mfr = "CentraLite", model = "3320" },
  { mfr = "CentraLite", model = "3321" },
  { mfr = "CentraLite", model = "3321-S" },
  { mfr = "SmartThings", model = "multiv4" },
  { mfr = "Samjin", model = "multi" },
  { mfr = "Third Reality, Inc", model = "3RVS01031Z" }
}

local function can_handle_zigbee_multi_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(MULTI_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function multi_sensor_report_handler(driver, device, zb_rx)
  local x, y, z
  for i,v in ipairs(zb_rx.body.zcl_body.attr_records) do
    if (v.attr_id.value == multi_utils.AXIS_X_ATTR) then
      y = v.data.value
    elseif (v.attr_id.value == multi_utils.AXIS_Y_ATTR) then
      z = v.data.value
    elseif (v.attr_id.value == multi_utils.AXIS_Z_ATTR) then
      x = v.data.value
    elseif (v.attr_id.value == multi_utils.ACCELERATION_ATTR) then
      multi_utils.handle_acceleration_report(device, v.data.value)
    end
  end
  multi_utils.handle_three_axis_report(device, x, y, z)
end

local function zone_status_change_handler(driver, device, zb_rx)
  if not device.preferences["certifiedpreferences.garageSensor"] then
    contactSensor_defaults.ias_zone_status_change_handler(driver, device, zb_rx)
  end
end

local function zone_status_handler(driver, device, zone_status, zb_rx)
  if not device.preferences["certifiedpreferences.garageSensor"] then
    contactSensor_defaults.ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  end
end

local function do_init(driver, device)
  device:remove_configured_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
  device:remove_monitored_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
end

local function added_handler(self, device)
  device:emit_event(capabilities.accelerationSensor.acceleration.inactive())
  device:refresh()
end

local multi_sensor = {
  NAME = "Zigbee Multi Sensor",
  lifecycle_handlers = {
    added = added_handler,
    init = do_init
  },
  zigbee_handlers = {
    global = {
      [multi_utils.CUSTOM_ACCELERATION_CLUSTER] = {
        [zcl_commands.ReportAttribute.ID] = multi_sensor_report_handler,
        [zcl_commands.ReadAttributeResponse.ID] = multi_sensor_report_handler
      }
    },
    cluster = {
      [zcl_clusters.IASZone.ID] = {
        [zcl_clusters.IASZone.client.commands.ZoneStatusChangeNotification.ID] = zone_status_change_handler
      }
    },
    attr = {
      [zcl_clusters.IASZone.ID] = {
        [zcl_clusters.IASZone.attributes.ZoneStatus.ID] = zone_status_handler
      }
    }
  },
  sub_drivers = {
    require("multi-sensor/smartthings-multi"),
    require("multi-sensor/samjin-multi"),
    require("multi-sensor/centralite-multi"),
    require("multi-sensor/thirdreality-multi")
  },
  can_handle = can_handle_zigbee_multi_sensor
}
return multi_sensor
