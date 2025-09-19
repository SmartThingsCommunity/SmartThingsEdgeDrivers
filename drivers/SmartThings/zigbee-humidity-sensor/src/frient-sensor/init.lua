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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local configurationMap = require "configurations"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local HumidityMeasurement = zcl_clusters.RelativeHumidity
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement

local FRIENT_TEMP_HUMUDITY_SENSOR_FINGERPRINTS = {
  { mfr = "frient A/S", model = "HMSZB-110" },
  { mfr = "frient A/S", model = "HMSZB-120" }
}

local function can_handle_frient_sensor(opts, driver, device)
  for _, fingerprint in ipairs(FRIENT_TEMP_HUMUDITY_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.3,3.0)(driver, device)
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function do_configure(driver, device, event, args)
  device:configure()
  device.thread:call_with_delay(5, function()
    device:refresh()
  end)
end

local function info_changed(driver, device, event, args)
  for name, value in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local sensitivity = math.floor((device.preferences[name]) * 100 + 0.5)
      if (name == "temperatureSensitivity") then
        device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 3600, sensitivity))
      end
      if (name == "humiditySensitivity") then
        device:send(HumidityMeasurement.attributes.MeasuredValue:configure_reporting(device, 60, 3600, sensitivity))
      end
    end
  end
  device.thread:call_with_delay(5, function()
      device:refresh()
  end)
end

local frient_sensor = {
  NAME = "Frient Humidity Sensor",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = can_handle_frient_sensor
}

return frient_sensor
