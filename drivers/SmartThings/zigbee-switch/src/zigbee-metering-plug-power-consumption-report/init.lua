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
local capabilities = require "st.capabilities"
local zigbee_constants = require "st.zigbee.constants"
local energy_meter_defaults = require "st.zigbee.defaults.energyMeter_defaults"

local SimpleMetering = clusters.SimpleMetering

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value

  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'

  energy_meter_defaults.energy_meter_handler(driver, device, value, zb_rx)
end

local do_configure = function(self, device)
  device:configure()
end

local device_init = function(self, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
end

local zigbee_metering_plug_power_conumption_report = {
  NAME = "zigbee metering plug power consumption report",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    local can_handle = device:get_manufacturer() == "DAWON_DNS"
    if can_handle then
      local subdriver = require("zigbee-metering-plug-power-consumption-report")
      return true, subdriver
    else
      return false
    end
  end
}

return zigbee_metering_plug_power_conumption_report
