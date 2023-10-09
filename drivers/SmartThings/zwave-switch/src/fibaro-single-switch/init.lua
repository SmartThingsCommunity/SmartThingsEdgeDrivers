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
local ButtonDefaults = require "st.zwave.defaults.button"
local EnergyMeterDefaults = require "st.zwave.defaults.energyMeter"
local PowerMeterDefaults = require "st.zwave.defaults.powerMeter"
local SwitchDefaults = require "st.zwave.defaults.switch"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({ version=1 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version=3 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })

local FIBARO_SINGLE_SWITCH_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x0403, model = 0x1000}, -- Fibaro Switch
  {mfr = 0x010F, prod = 0x0403, model = 0x2000}, -- Fibaro Switch
  {mfr = 0x010F, prod = 0x0403, model = 0x3000} -- Fibaro Switch
}

local function can_handle_fibaro_single_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FIBARO_SINGLE_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-single-switch")
      return true, subdriver
    end
  end
  return false
end

local function central_scene_notification_handler(self, device, cmd)
  if cmd.src_channel == nil or cmd.src_channel == 0 then
    ButtonDefaults.zwave_handlers[cc.CENTRAL_SCENE][CentralScene.NOTIFICATION](self, device, cmd)
  end
end

-- Device appears to not handle SwitchMultilevel commands despite reporting that the CC
-- is supported. DTH uses basic so that is replicated here. For similar behavior see the
-- Aeotec Smart Switch driver
local function switch_handler_factory(value)
  return function(driver, device, cmd)
    device:send(Basic:Set({value=value}))
  end
end

local function meter_report_handler(self, device, cmd)
  if cmd.src_channel == nil or cmd.src_channel == 0 then
    if cmd.args.scale == Meter.scale.electric_meter.KILOWATT_HOURS then
      EnergyMeterDefaults.zwave_handlers[cc.METER][Meter.REPORT](self, device, cmd)
    elseif cmd.args.scale == Meter.scale.electric_meter.WATTS then
      PowerMeterDefaults.zwave_handlers[cc.METER][Meter.REPORT](self, device, cmd)
    end
  end
end

local function switch_binary_report_handler(self, device, cmd)
  if cmd.src_channel == nil or cmd.src_channel == 0 then
    SwitchDefaults.zwave_handlers[cc.SWITCH_BINARY][SwitchBinary.REPORT](self, device, cmd)
  end
end

local fibaro_single_switch = {
  NAME = "fibaro single switch",
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    },
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_binary_report_handler
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_handler_factory(0xFF),
      [capabilities.switch.commands.off.NAME] = switch_handler_factory(0x00),
    }
  },
  can_handle = can_handle_fibaro_single_switch,
}

return fibaro_single_switch
