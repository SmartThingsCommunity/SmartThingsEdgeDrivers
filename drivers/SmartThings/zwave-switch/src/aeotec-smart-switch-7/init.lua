-- Copyright 2023 SmartThings
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
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=1 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local POWER_UNIT_WATT = "W"
local ENERGY_UNIT_KWH = "kWh"

local FINGERPRINTS = {
  { mfr = 0x0086, prod = 0x0003, model = 0x00AF, deviceProfile = 'aeotec-smart-switch-7-eu' }, -- EU
  { mfr = 0x0086, prod = 0x0103, model = 0x0017, deviceProfile = 'aeotec-smart-switch-7-us' }  -- US
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, nil, fingerprint.prodId) then
      local subdriver = require('aeotec-smart-switch-7')
      return true, subdriver
    end
  end
  return false
end

local function emit_power_consumption_report_event(device, value, channel)
  -- powerConsumptionReport report interval
  local current_time = os.time()
  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_time = last_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
  if current_time < next_time then
    return
  end
  device:set_field(LAST_REPORT_TIME, current_time, { persist = true })
  local raw_value = value.value * 1000 -- 'Wh'

  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state('main', capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event_for_endpoint(channel, capabilities.powerConsumptionReport.powerConsumption({
    energy = raw_value,
    deltaEnergy = delta_energy
  }))
end

local function meter_report_handler(driver, device, cmd, zb_rx)
  if cmd.args.scale == Meter.scale.electric_meter.KILOWATT_HOURS then
    local event_arguments = {
      value = cmd.args.meter_value,
      unit = ENERGY_UNIT_KWH
    }
    -- energyMeter
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.energyMeter.energy(event_arguments)
    )

    emit_power_consumption_report_event(device, { value = event_arguments.value }, cmd.src_channel)
  elseif cmd.args.scale == Meter.scale.electric_meter.WATTS then
    local event_arguments = {
      value = cmd.args.meter_value,
      unit = POWER_UNIT_WATT
    }
    -- powerMeter
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.powerMeter.power(event_arguments)
    )
  end
end

-- Despite the NIF indicating that this device supports the Switch Multilevel
-- command class, the device will not respond to multilevel commands. Note that
-- this applies at least to the Aeotec Smart Switch 6 and 7
local function on_off_factory(onOff)
  return function(driver, device, cmd)
    device:send(Basic:Set({value=onOff}))
    device.thread:call_with_delay(3, function() device:send(SwitchBinary:Get({})) end)
  end
end

local aeotec_smart_switch_7 = {
  NAME = "Aeotec Smart Switch 7",
  supported_capabilities = {
    capabilities.switch,
    capabilities.energyMeter,
    capabilities.powerMeter,
    capabilities.powerConsumptionReport
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_off_factory(0xFF),
      [capabilities.switch.commands.off.NAME] = on_off_factory(0x00)
    }
  },
  zwave_handlers = {
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    }
  },
  can_handle = can_handle
}

return aeotec_smart_switch_7