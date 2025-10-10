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
  sub_drivers = require("zigbee-switch-power.sub_drivers"),
  can_handle = require("zigbee-switch-power.can_handle"),
}

return zigbee_switch_power
