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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local AEON_SMART_STRIP_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0003, model = 0x000B}, -- Aeon Smart Strip DSC11-ZWUS
}

local ENERGY_UNIT_KWH = "kWh"
local ENERGY_UNIT_KVAH = "kVAh"
local POWER_UNIT_WATT = "W"

--- Determine whether the passed device is Aeon smart strip
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_aeon_smart_strip(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEON_SMART_STRIP_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("aeon-smart-strip")
      return true, subdriver
    end
  end
  return false
end

local function binary_event_helper(self, device, cmd)
  local value = cmd.args.value and cmd.args.value or cmd.args.target_value
  local event = value == SwitchBinary.value.OFF_DISABLE and capabilities.switch.switch.off() or capabilities.switch.switch.on()
  if cmd.src_channel == 0 then
    device:emit_event_for_endpoint(cmd.src_channel, event)
    for ep = 1,4 do
      device:emit_event_for_endpoint(ep, event)
      device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS}), string.format("switch%d", ep + 2))
    end
  else
    device:emit_event_for_endpoint(cmd.src_channel, event)
    device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}), string.format("switch%d", cmd.src_channel + 2))
    device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS}), string.format("switch%d", cmd.src_channel + 2))
  end
end

local function meter_report_handler(self, device, cmd)
  local value
  local unit
  if cmd.args.scale == Meter.scale.electric_meter.KILOWATT_HOURS then
    value = utils.round(cmd.args.meter_value * 100 ) / 100
    unit = ENERGY_UNIT_KWH
  elseif cmd.args.scale == Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS then
    value = utils.round(cmd.args.meter_value * 100 ) / 100
    unit = ENERGY_UNIT_KVAH
  elseif cmd.args.scale == Meter.scale.electric_meter.WATTS then
    value = utils.round(cmd.args.meter_value)
    unit = POWER_UNIT_WATT
  end

  if cmd.src_channel == 0 then
    if cmd.args.scale < Meter.scale.electric_meter.WATTS then
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.energyMeter.energy({value = value, unit = unit }))
      for ep = 1,4 do
        device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}), string.format("switch%d", ep + 2))
      end
    else
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.powerMeter.power({value = value, unit = unit }))
    end
  elseif cmd.src_channel > 2 then
    if cmd.args.scale < Meter.scale.electric_meter.WATTS then
      device:emit_event_for_endpoint(cmd.src_channel - 2, capabilities.energyMeter.energy({value = value, unit = unit }))
    else
      device:emit_event_for_endpoint(cmd.src_channel - 2, capabilities.powerMeter.power({value = value, unit = unit }))
    end
  end
end

local aeon_smart_strip = {
  NAME = "Aeon smart strip",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = binary_event_helper
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = binary_event_helper
    },
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    }
  },
  can_handle = can_handle_aeon_smart_strip,
}

return aeon_smart_strip
