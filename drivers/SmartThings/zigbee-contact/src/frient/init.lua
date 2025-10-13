-- Copyright 2025 SmartThings
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

local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local configurationMap = require "configurations"
local capabilities = require "st.capabilities"

local IASZone = clusters.IASZone
local TemperatureMeasurement = clusters.TemperatureMeasurement
local TEMPERATURE_ENDPOINT = 0x26

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  device:emit_event(zone_status:is_alarm1_set() and capabilities.contactSensor.contact.open() or capabilities.contactSensor.contact.closed())
  if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
    device:emit_event(zone_status:is_tamper_set() and capabilities.tamperAlert.tamper.detected() or capabilities.tamperAlert.tamper.clear())
  end
end

local function ias_zone_status_attr_handler(driver, device, attr_val, zb_rx)
  generate_event_from_zone_status(driver, device, attr_val, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)

  battery_defaults.build_linear_voltage_init(2.3, 3.0)(driver, device)

  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function added_handler(driver, device)
  if device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) then
    device:send(TemperatureMeasurement.attributes.MaxMeasuredValue:read(device))
    device:send(TemperatureMeasurement.attributes.MinMeasuredValue:read(device))
  end
end

local function do_configure(driver, device)
  device:configure()
  device:refresh()
end

local function info_changed(driver, device, event, args)
  for name, value in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      if (name == "temperatureSensitivity") then
        local input = device.preferences.temperatureSensitivity
        local temperatureSensitivity = math.floor(input * 100 + 0.5)
        device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 1800, temperatureSensitivity):to_endpoint(TEMPERATURE_ENDPOINT))
      end
    end
  end
end

local frient_sensor = {
  NAME = "Frient Contact Temperature Tamper",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler,
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return (device:get_manufacturer() == "frient A/S" and (device:get_model() == "WISZB-120" or device:get_model() == "WISZB-121" or device:get_model() == "WISZB-131"))
  end
}

return frient_sensor
