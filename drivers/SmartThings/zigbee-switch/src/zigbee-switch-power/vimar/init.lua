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

local constants = require "st.zigbee.constants"
local device_management = require "st.zigbee.device_management"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local ElectricalMeasurement = zcl_clusters.ElectricalMeasurement

local VIMAR_FINGERPRINTS = {
  { mfr = "Vimar", model = "Mains_Power_Outlet_v1.0" }
}

local function can_handle_vimar_switch_power(opts, driver, device)
  for _, fingerprint in ipairs(VIMAR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function do_configure(driver, device)
  device:configure()
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1, {persist = true})
  device:send(device_management.build_bind_request(device, ElectricalMeasurement.ID, driver.environment_info.hub_zigbee_eui))
  device:send(ElectricalMeasurement.attributes.ActivePower:configure_reporting(device, 1, 15, 1))
  device:refresh()
end

local vimar_switch_power = {
  NAME = "Vimar Smart Actuator with Power Metering",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_vimar_switch_power
}

return vimar_switch_power
