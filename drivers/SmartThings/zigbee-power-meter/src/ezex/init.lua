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
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local energy_meter_defaults = require "st.zigbee.defaults.energyMeter_defaults"

local ZIGBEE_POWER_METER_FINGERPRINTS = {
  { model = "E240-KR080Z0-HA" }
}

local is_ezex_power_meter = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_POWER_METER_FINGERPRINTS) do
      if device:get_model() == fingerprint.model then
          return true
      end
  end

  return false
end

local instantaneous_demand_configuration = {
  cluster = clusters.SimpleMetering.ID,
  attribute = clusters.SimpleMetering.attributes.InstantaneousDemand.ID,
  minimum_interval = 1,
  maximum_interval = 3600,
  data_type = clusters.SimpleMetering.attributes.InstantaneousDemand.base_type,
  reportable_change = 500
}

local do_configure = function(self, device)
  device:refresh()
  device:configure()
end

local device_init = function(self, device)
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000000, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, {persist = true})

  device:add_monitored_attribute(instantaneous_demand_configuration)
  device:add_configured_attribute(instantaneous_demand_configuration)
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value_miliwatts = value.value
  local raw_value_watts = raw_value_miliwatts / 1000
  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value_watts - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({energy = raw_value_watts, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'

  energy_meter_defaults.energy_meter_handler(driver, device, value, zb_rx)
end

local ezex_power_meter_handler = {
  NAME = "ezex power meter handler",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
  },
  can_handle = is_ezex_power_meter
}

return ezex_power_meter_handler
