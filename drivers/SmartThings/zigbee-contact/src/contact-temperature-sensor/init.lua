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

local CONTACT_TEMPERATURE_SENSOR_FINGERPRINTS = {
  { mfr = "CentraLite", model = "3300-S" },
  { mfr = "CentraLite", model = "3300" },
  { mfr = "CentraLite", model = "3320-L" },
  { mfr = "CentraLite", model = "3323-G" },
  { mfr = "CentraLite", model = "Contact Sensor-A" },
  { mfr = "Visonic", model = "MCT-340 E" },
  { mfr = "Visonic", model = "MCT-340 SMA" },
  { mfr = "Ecolink", model = "4655BC0-R" },
  { mfr = "Ecolink", model = "DWZB1-ECO" },
  { mfr = "iMagic by GreatStar", model = "1116-S" },
  { mfr = "Bosch", model = "RFMS-ZBMS" },
  { mfr = "Megaman", model = "MS601/z1" },
  { mfr = "AduroSmart Eria", model = "CSW_ADUROLIGHT" },
  { mfr = "ADUROLIGHT", model = "CSW_ADUROLIGHT" },
  { mfr = "Sercomm Corp.", model = "SZ-DWS04" },
  { mfr = "DAWON_DNS", model = "SS-B100-ZB" },
  { mfr = "frient A/S", model = "WISZB-120" },
  { mfr = "frient A/S", model = "WISZB-121" },
  { mfr = "Compacta", model = "ZBWDS" }
}

local function can_handle_contact_temperature_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(CONTACT_TEMPERATURE_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)

  battery_defaults.build_linear_voltage_init(2.1, 3.0)(driver, device)

  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local contact_temperature_sensor = {
  NAME = "Contact Temperature Sensor",
  lifecycle_handlers = {
    init = device_init
  },
  sub_drivers = {
    require("contact-temperature-sensor/ecolink-contact"),
    require("contact-temperature-sensor/frient-sensor")
  },
  can_handle = can_handle_contact_temperature_sensor
}

return contact_temperature_sensor
