-- Copyright 2025 SmartThings
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
local device_management = require "st.zigbee.device_management"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local log = require "log"

local ZIGBEE_POWER_METER_FINGERPRINTS = {
  { mfr = "BITUO TECHNIK", model = "SPM01-E0" },
  { mfr = "BITUO TECHNIK", model = "SPM01X" },
  { mfr = "BITUO TECHNIK", model = "SDM02-E0" },
  { mfr = "BITUO TECHNIK", model = "SDM02X" },
  { mfr = "BITUO TECHNIK", model = "SPM02-E0" },
  { mfr = "BITUO TECHNIK", model = "SPM02X" },
  { mfr = "BITUO TECHNIK", model = "SDM01W" },
  { mfr = "BITUO TECHNIK", model = "SDM01B" },
}

local PHASE_A_CONFIGURATION = {
  {
    cluster = SimpleMetering.ID,
    attribute = SimpleMetering.attributes.CurrentSummationDelivered.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = SimpleMetering.attributes.CurrentSummationDelivered.base_type,
    reportable_change = 0
  },
  {
    cluster = SimpleMetering.ID,
    attribute = 0x0001,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = SimpleMetering.attributes.CurrentSummationDelivered.base_type,
    reportable_change = 0
  },
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.ActivePower.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.ActivePower.base_type,
    reportable_change = 0
  },
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.RMSVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.RMSVoltage.base_type,
    reportable_change = 0
  },
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.RMSCurrent.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.RMSCurrent.base_type,
    reportable_change = 0
  }
}
local PHASE_B_CONFIGURATION = {
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.ActivePowerPhB.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.ActivePowerPhB.base_type,
    reportable_change = 0
  },
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.RMSVoltagePhB.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.RMSVoltagePhB.base_type,
    reportable_change = 0
  },
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.RMSCurrentPhB.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.RMSCurrentPhB.base_type,
    reportable_change = 0
  },
}
local PHASE_C_CONFIGURATION = {
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.ActivePowerPhC.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.ActivePowerPhC.base_type,
    reportable_change = 0
  },
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.RMSVoltagePhC.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.RMSVoltagePhC.base_type,
    reportable_change = 0
  },
  {
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.RMSCurrentPhC.ID,
    minimum_interval = 30,
    maximum_interval = 120,
    data_type = ElectricalMeasurement.attributes.RMSCurrentPhC.base_type,
    reportable_change = 0
  }
}

local is_bituo_power_meter = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_POWER_METER_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function energy_handler(driver, device, value, zb_rx)
  local multiplier = 1
  local divisor = 100
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

local function generic_handler_factory(component_name, capability, multiplier, divisor, unit)
  return function(driver, device, value, zb_rx)
    local component = device.profile.components[component_name]
    if component ~= nil then
      local raw_value = value.value * multiplier / divisor
      device:emit_component_event(component, capability({value = raw_value, unit = unit}))
    end
  end
end

local refresh = function(driver, device, cmd)
  device:refresh()
end

local function resetEnergyMeter(self, device)
  device:send(clusters.OnOff.server.commands.On(device))
  -- Reset Power consumption
  device:set_field(constants.ENERGY_METER_OFFSET, 0, {persist = true})
  device:set_field("LAST_SAVE_TICK", os.time(), {persist = false})
end
local function do_configure(driver, device)
  device:configure()
  --device:send(device_management.build_bind_request(device, clusters.SimpleMetering.ID, driver.environment_info.hub_zigbee_eui))
  --device:send(device_management.build_bind_request(device, clusters.ElectricalMeasurement.ID, driver.environment_info.hub_zigbee_eui))
  device:refresh()
end

local device_init = function(self, device)
  for _, attribute in ipairs(PHASE_A_CONFIGURATION) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
  if string.find(device:get_model(), "SDM02") or string.find(device:get_model(), "SPM02") or string.find(device:get_model(), "SDM01W") then
    log.debug("2 phase")
    for _, attribute in ipairs(PHASE_B_CONFIGURATION) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
  if string.find(device:get_model(), "SPM02") or string.find(device:get_model(), "SDM01W") then
    log.debug("3 phase")
    for _, attribute in ipairs(PHASE_C_CONFIGURATION) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local bituo_power_meter_handler = {
  NAME = "bituo power meter handler",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
  },
  zigbee_handlers = {
    attr = {
      [clusters.SimpleMetering.ID] = {
        [clusters.SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_handler,
        [0x0001] = generic_handler_factory("TotalReverseEnergy", capabilities.energyMeter.energy, 1, 100, "kWh"),
        },
      [clusters.ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = generic_handler_factory("PhaseA", capabilities.powerMeter.power, 1, 1, "W"),
        [ElectricalMeasurement.attributes.ActivePowerPhB.ID] = generic_handler_factory("PhaseB", capabilities.powerMeter.power, 1, 1, "W"),
        [ElectricalMeasurement.attributes.ActivePowerPhC.ID] = generic_handler_factory("PhaseC", capabilities.powerMeter.power, 1, 1, "W"),
        [ElectricalMeasurement.attributes.RMSVoltage.ID] = generic_handler_factory("PhaseA", capabilities.voltageMeasurement.voltage, 1, 100, "V"),
        [ElectricalMeasurement.attributes.RMSVoltagePhB.ID] = generic_handler_factory("PhaseB", capabilities.voltageMeasurement.voltage, 1, 100, "V"),
        [ElectricalMeasurement.attributes.RMSVoltagePhC.ID] = generic_handler_factory("PhaseC", capabilities.voltageMeasurement.voltage, 1, 100, "V"),
        [ElectricalMeasurement.attributes.RMSCurrent.ID] = generic_handler_factory("PhaseA", capabilities.currentMeasurement.current, 1, 100, "A"),
        [ElectricalMeasurement.attributes.RMSCurrentPhB.ID] = generic_handler_factory("PhaseB", capabilities.currentMeasurement.current, 1, 100, "A"),
        [ElectricalMeasurement.attributes.RMSCurrentPhC.ID] = generic_handler_factory("PhaseC", capabilities.currentMeasurement.current, 1, 100, "A")
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    },
    [capabilities.energyMeter.ID] = {
      [capabilities.energyMeter.commands.resetEnergyMeter.NAME] = resetEnergyMeter,
    },
  },
  can_handle = is_bituo_power_meter
}

return bituo_power_meter_handler
