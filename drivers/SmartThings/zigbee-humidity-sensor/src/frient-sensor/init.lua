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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local configurationMap = require "configurations"

local HEIMAN_TEMP_HUMUDITY_SENSOR_FINGERPRINTS = {
  { mfr = "frient A/S", model = "HMSZB-110" },
}

local function can_handle_heiman_sensor(opts, driver, device)
  for _, fingerprint in ipairs(HEIMAN_TEMP_HUMUDITY_SENSOR_FINGERPRINTS) do
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
      device:add_monitored_attribute(attribute)
    end
  end
end

local heiman_sensor = {
  NAME = "Heiman Humidity Sensor",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = can_handle_heiman_sensor
}

return heiman_sensor
