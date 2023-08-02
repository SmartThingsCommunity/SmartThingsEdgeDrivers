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

local ZWAVE_DUAL_SWITCH_FINGERPRINTS = {
  { mfr = 0x0086, prod = 0x0103, model = 0x008C }, -- Aeotec Switch 1
  { mfr = 0x0086, prod = 0x0003, model = 0x008C }, -- Aeotec Switch 1
  { mfr = 0x0258, prod = 0x0003, model = 0x008B }, -- NEO Coolcam Switch 1
  { mfr = 0x0258, prod = 0x0003, model = 0x108B }, -- NEO Coolcam Switch 1
  { mfr = 0x0312, prod = 0xC000, model = 0xC004 }, -- EVA Switch 1
  { mfr = 0x0312, prod = 0xFF00, model = 0xFF05 }, -- Minoston Switch 1
  { mfr = 0x0312, prod = 0xC000, model = 0xC007 }, -- Evalogik Switch 1
  { mfr = 0x010F, prod = 0x1B01, model = 0x1000 }, -- Fibaro Walli Double Switch
  { mfr = 0x027A, prod = 0xA000, model = 0xA003 }  -- Zooz Double Plug
}

local function can_handle_zwave_dual_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_DUAL_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zwave-dual-switch")
      return true, subdriver
    end
  end
  return false
end

local zwave_dual_switch = {
  NAME = "zwave dual switch",
  can_handle = can_handle_zwave_dual_switch
}

return zwave_dual_switch
