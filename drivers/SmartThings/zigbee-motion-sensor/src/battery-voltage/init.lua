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

local DEVICES_REPORTING_BATTERY_VOLTAGE = {
  { mfr = "Bosch", model = "RFPR-ZB" },
  { mfr = "Bosch", model = "RFDL-ZB-MS" },
  { mfr = "Ecolink", model = "PIRZB1-ECO" },
  { mfr = "ADUROLIGHT", model = "VMS_ADUROLIGHT" },
  { mfr = "AduroSmart Eria", model = "VMS_ADUROLIGHT" }
}

local can_handle_battery_voltage = function(opts, driver, device, ...)
  for _, fingerprint in ipairs(DEVICES_REPORTING_BATTERY_VOLTAGE) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end


local battery_voltage_motion = {
  NAME = "Battery Voltage Motion Sensor",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0)
  },
  can_handle = can_handle_battery_voltage
}

return battery_voltage_motion
