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

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"

local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement

local SWITCH_POWER_FINGERPRINTS = {
  { mfr = "Vimar", model = "Mains_Power_Outlet_v1.0" },
  { model = "PAN18-v1.0.7" },
  { model = "E210-KR210Z1-HA" },
  { mfr = "Aurora", model = "Smart16ARelay51AU" },
  { mfr = "Develco Products A/S", model = "Smart16ARelay51AU" },
  { mfr = "Jasco Products", model = "45853" },
  { mfr = "Jasco Products", model = "45856" },
  { mfr = "MEGAMAN", model = "SH-PSUKC44B-E" },
  { mfr = "ClimaxTechnology", model = "PSM_00.00.00.35TC" },
  { mfr = "SALUS", model = "SX885ZB" },
  { mfr = "AduroSmart Eria", model = "AD-SmartPlug3001" },
  { mfr = "AduroSmart Eria", model = "BPU3" },
  { mfr = "AduroSmart Eria", model = "BDP3001" }
}

local function can_handle_zigbee_switch_power(opts, driver, device)
  for _, fingerprint in ipairs(SWITCH_POWER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-switch-power")
      return true, subdriver
    end
  end
  return false
end

local function active_power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) or 10

  raw_value = raw_value / divisor

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local function instantaneous_demand_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 10

  raw_value = raw_value / divisor

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local zigbee_switch_power = {
  NAME = "Zigbee Switch Power",
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = active_power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler
      }
    }
  },
  sub_drivers = {
    require("zigbee-switch-power/aurora-relay"),
    require("zigbee-switch-power/vimar")
  },
  can_handle = can_handle_zigbee_switch_power
}

return zigbee_switch_power
