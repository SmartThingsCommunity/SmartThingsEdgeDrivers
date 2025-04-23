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

local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local configurationMap = require "configurations"
local capabilities = require "st.capabilities"

local IASZone = clusters.IASZone
local TemperatureMeasurement = clusters.TemperatureMeasurement
local TEMPERATURE_ENDPOINT = 0x26
local DEFAULT_TEMPERATURE_SENSITIVITY = 100


local FRIENT_CONTACT_TEMPERATURE_FINGERPRINTS = {
  { mfr = "frient A/S", model = "WISZB-120", has_temperature = true,  has_tamper = true },
  { mfr = "frient A/S", model = "WISZB-121", has_temperature = false, has_tamper = false }
}

local function get_device_capabilities(device)
  for _, fingerprint in ipairs(FRIENT_CONTACT_TEMPERATURE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return fingerprint
    end
  end
  return nil
end

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  device:emit_event(zone_status:is_alarm1_set() and capabilities.contactSensor.contact.open() or capabilities.contactSensor.contact.closed())
  local device_capabilities = get_device_capabilities(device)
  if device_capabilities ~= nil and device_capabilities.has_tamper then
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
      device:add_monitored_attribute(attribute)
    end
  end
end

local function added_handler(driver, device)
  local device_capabilities = get_device_capabilities(device)
  if device_capabilities ~= nil and device_capabilities.has_temperature then
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
    return (device:get_manufacturer() == "frient A/S" and (device:get_model() == "WISZB-120" or device:get_model() == "WISZB-121"))
  end
}

return frient_sensor
