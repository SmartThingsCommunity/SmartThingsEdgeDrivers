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
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"

local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement
local PowerConfiguration = clusters.PowerConfiguration

local HEIMAN_TEMP_HUMUDITY_SENSOR_FINGERPRINTS = {
  { mfr = "Heiman", model = "b467083cfc864f5e826459e5d8ea6079" },
  { mfr = "HEIMAN", model = "888a434f3cfc47f29ec4a3a03e9fc442" },
  { mfr = "HEIMAN", model = "HT-EM" },
  { mfr = "HEIMAN", model = "HT-EF-3.0" }
}

local function can_handle_heiman_sensor(opts, driver, device)
  for _, fingerprint in ipairs(HEIMAN_TEMP_HUMUDITY_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function do_refresh(driver, device)
  device:send(RelativeHumidity.attributes.MeasuredValue:read(device):to_endpoint(0x02))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function do_configure(driver, device)
  device:send(device_management.build_bind_request(device, RelativeHumidity.ID, driver.environment_info.hub_zigbee_eui):to_endpoint(0x02))
  device:configure()
  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(device, 30, 3600, 100):to_endpoint(0x02))
  do_refresh(driver, device)
end

local heiman_sensor = {
  NAME = "Heiman Humidity Sensor",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = can_handle_heiman_sensor
}

return heiman_sensor
