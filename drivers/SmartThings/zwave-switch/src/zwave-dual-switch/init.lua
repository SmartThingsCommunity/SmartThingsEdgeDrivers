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
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local ZWAVE_DUAL_SWITCH_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0103, model = 0x008C}, -- Aeotec Switch 1
  {mfr = 0x0086, prod = 0x0003, model = 0x008C}, -- Aeotec Switch 1
  {mfr = 0x0258, prod = 0x0003, model = 0x008B}, -- NEO Coolcam Switch 1
  {mfr = 0x0258, prod = 0x0003, model = 0x108B}, -- NEO Coolcam Switch 1
  {mfr = 0x0312, prod = 0xC000, model = 0xC004}, -- EVA Switch 1
  {mfr = 0x0312, prod = 0xFF00, model = 0xFF05}, -- Minoston Switch 1
  {mfr = 0x0312, prod = 0xC000, model = 0xC007}, -- Evalogik Switch 1
  {mfr = 0x010F, prod = 0x1B01, model = 0x1000}, -- Fibaro Walli Double Switch
  {mfr = 0x027A, prod = 0xA000, model = 0xA003} -- Zooz Double Plug
}

local function can_handle_zwave_dual_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_DUAL_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function device_added(self, device)
  device:refresh()
end

local function endpoint_to_component(device, endpoint)
  if endpoint == 2 then
    return "switch1"
  else
    return "main"
  end
end

local function component_to_endpoint(device, component)
  if component == "switch1" then
    return {2}
  else
    return {1}
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function basic_set_handler(driver, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  local event = value == 0x00 and capabilities.switch.switch.off() or capabilities.switch.switch.on()

  device:emit_event_for_endpoint(cmd.src_channel, event)
end

local zwave_dual_switch = {
  NAME = "zwave dual switch",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = map_components
  },
  can_handle = can_handle_zwave_dual_switch
}

return zwave_dual_switch
