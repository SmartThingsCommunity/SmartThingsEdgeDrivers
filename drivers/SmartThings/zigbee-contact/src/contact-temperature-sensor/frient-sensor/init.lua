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

local TemperatureMeasurement = clusters.TemperatureMeasurement

local FRIENT_CONTACT_TEMPERATURE_FINGERPRINTS = {
  { mfr = "frient A/S", model = "WISZB-120" },
  { mfr = "frient A/S", model = "WISZB-121" }
}

local function can_handle_frient_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(FRIENT_CONTACT_TEMPERATURE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
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

local function do_configure(driver, device)
  device:configure()
  device:send(TemperatureMeasurement.server.attributes.MeasuredValue:configure_reporting(device, 30, 1800, 100):to_endpoint(0x26))
  device:refresh()
end

local frient_sensor = {
  NAME = "Frient Contact Temperature",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  can_handle = can_handle_frient_sensor
}

return frient_sensor
