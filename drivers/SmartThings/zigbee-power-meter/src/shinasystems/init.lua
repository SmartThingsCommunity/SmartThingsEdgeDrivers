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
local ElectricalMeasurement = clusters.ElectricalMeasurement

local ZIGBEE_POWER_METER_FINGERPRINTS = {
  { model = "PMM-300Z1" },
  { model = "PMM-300Z2" },
  { model = "PMM-300Z3" }
}

local POWERMETER_CONFIGURATION_V2 = {
  {
    cluster = SimpleMetering.ID,
    attribute = SimpleMetering.attributes.CurrentSummationDelivered.ID,
    minimum_interval = 5,
    maximum_interval = 300,
    data_type = SimpleMetering.attributes.CurrentSummationDelivered.base_type,
    reportable_change = 1
  },
  {
    cluster = SimpleMetering.ID,
    attribute = SimpleMetering.attributes.InstantaneousDemand.ID,
    minimum_interval = 5,
    maximum_interval = 300,
    data_type = SimpleMetering.attributes.InstantaneousDemand.base_type,
    reportable_change = 1
  },
  { -- reporting : no
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.ActivePower.ID,
    minimum_interval = 0,
    maximum_interval = 65535,
    data_type = ElectricalMeasurement.attributes.ActivePower.base_type,
    reportable_change = 1
  }
}

local is_shinasystems_power_meter = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_POWER_METER_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true
    end
  end

  return false
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local multiplier = device:get_field(constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 1000
  local raw_value = value.value
  local raw_value_kilowatts = raw_value * multiplier/divisor

  local offset = device:get_field(constants.ENERGY_METER_OFFSET) or 0
  if raw_value_kilowatts < offset then
    --- somehow our value has gone below the offset, so we'll reset the offset, since the device seems to have
    offset = 0
    device:set_field(constants.ENERGY_METER_OFFSET, offset, {persist = true})
  end
  raw_value_kilowatts = raw_value_kilowatts - offset

  local raw_value_watts = raw_value_kilowatts*1000
  local delta_tick
  local last_save_ticks = device:get_field("LAST_SAVE_TICK")

  if last_save_ticks == nil then last_save_ticks = 0 end
  delta_tick = os.time() - last_save_ticks

  -- wwst energy certification : powerConsumptionReport capability values should be updated every 15 minutes.
  -- Check if 15 minutes have passed since the reporting time of current_power_consumption.
  if delta_tick >= 15*60 then
    local delta_energy = 0.0
    local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
    if current_power_consumption ~= nil then
      delta_energy = math.max(raw_value_watts - current_power_consumption.energy, 0.0)
    end
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({energy = raw_value_watts, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'

    local curr_save_tick = last_save_ticks + 15*60 -- Set the time to a regular interval by adding 15 minutes to the existing last_save_ticks.
    -- If the time 15 minutes from now is less than the current time, set the current time as the last time.
    if curr_save_tick + 15*60 < os.time() then
      curr_save_tick = os.time()
    end
    device:set_field("LAST_SAVE_TICK", curr_save_tick, {persist = false})
  end
  device:emit_event(capabilities.energyMeter.energy({value = raw_value_kilowatts, unit = "kWh"}))
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()
end

local device_init = function(self, device)
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
  for _, attribute in ipairs(POWERMETER_CONFIGURATION_V2) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local shinasystems_power_meter_handler = {
  NAME = "shinasystems power meter handler",
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
  can_handle = is_shinasystems_power_meter
}

return shinasystems_power_meter_handler
