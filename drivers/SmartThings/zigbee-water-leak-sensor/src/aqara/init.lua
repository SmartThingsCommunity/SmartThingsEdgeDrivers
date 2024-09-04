-- Copyright 2024 SmartThings
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
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local TemperatureMeasurement = (require "st.zigbee.zcl.clusters").TemperatureMeasurement
local PowerConfiguration = clusters.PowerConfiguration
local IASZone = clusters. IASZone
local EnrollResponseCode = IASZone.types.EnrollResponseCode


local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.flood.agl02" }
}

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_added(driver, device)
  device:emit_event(capabilities.waterSensor.water.dry())
  device:emit_event(capabilities.battery.battery(100))
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)
end

local do_configure = function(self, device)
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 3600, 1))
  device:send(IASZone.server.commands.ZoneEnrollResponse(device, EnrollResponseCode.SUCCESS, 0x00))
  device:refresh()
end

local aqara_contact_handler = {
  NAME = "Aqara water leak sensor",
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = function() end
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = is_aqara_products
}

return aqara_contact_handler
