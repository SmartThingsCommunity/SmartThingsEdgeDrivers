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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local SimpleMetering = zcl_clusters.SimpleMetering
local ElectricalMeasurement = zcl_clusters.ElectricalMeasurement

local ZIGBEE_METERING_SWITCH_FINGERPRINTS = {
  { model = "E240-KR116Z-HA" }
}

local is_zigbee_ezex_switch = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_METERING_SWITCH_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      local subdriver = require("ezex")
      return true, subdriver
    end
  end

  return false
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  raw_value = raw_value / 1000000
  device:emit_event(capabilities.energyMeter.energy({value = raw_value, unit = "kWh" }))
end

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  raw_value = raw_value / 1000
  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W" }))
end

local ezex_switch_handler = {
  NAME = "ezex switch handler",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = power_meter_handler,
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      }
    }
  },
  can_handle = is_zigbee_ezex_switch
}

return ezex_switch_handler
