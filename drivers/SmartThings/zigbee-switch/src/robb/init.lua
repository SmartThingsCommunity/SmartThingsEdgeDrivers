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

local constants = require "st.zigbee.constants"

local SimpleMetering = zcl_clusters.SimpleMetering
local ElectricalMeasurement = zcl_clusters.ElectricalMeasurement

local ROBB_DIMMER_FINGERPRINTS = {
  { mfr = "ROBB smarrt", model = "ROB_200-011-0" },
  { mfr = "ROBB smarrt", model = "ROB_200-014-0" }
}

local function is_robb_dimmer(opts, driver, device)
  for _, fingerprint in ipairs(ROBB_DIMMER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("robb")
      return true, subdriver
    end
  end
  return false
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 1000000

  raw_value = raw_value * multiplier / divisor
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value, unit = "kWh" }))
end

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(constants.ELECTRICAL_MEASUREMENT_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) or 10

  raw_value = raw_value * multiplier / divisor
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local robb_dimmer_handler = {
  NAME = "ROBB smarrt dimmer",
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
  can_handle = is_robb_dimmer
}

return robb_dimmer_handler
