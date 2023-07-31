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

local MULTI_METERING_SWITCH_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0003, model = 0x0084}, -- Aeotec Nano Switch 1
  {mfr = 0x0086, prod = 0x0103, model = 0x0084}, -- Aeotec Nano Switch 1
  {mfr = 0x0086, prod = 0x0203, model = 0x0084}, -- AU Aeotec Nano Switch 1
  {mfr = 0x027A, prod = 0xA000, model = 0xA004}, -- Zooz ZEN Power Strip 1
  {mfr = 0x015F, prod = 0x3102, model = 0x0201}, -- WYFY Touch 1-button Switch
  {mfr = 0x015F, prod = 0x3102, model = 0x0202}, -- WYFY Touch 2-button Switch
  {mfr = 0x015F, prod = 0x3102, model = 0x0204}, -- WYFY Touch 4-button Switch
  {mfr = 0x015F, prod = 0x3111, model = 0x5102}, -- WYFY Touch 1-button Switch
  {mfr = 0x015F, prod = 0x3121, model = 0x5102}, -- WYFY Touch 2-button Switch
  {mfr = 0x015F, prod = 0x3141, model = 0x5102} -- WYFY Touch 4-button Switch
}

local function can_handle_multi_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(MULTI_METERING_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("multi-metering-switch")
      return true, subdriver
    end
  end
  return false
end

local multi_metering_switch = {
  NAME = "multi metering switch",
  can_handle = can_handle_multi_metering_switch,
  lazy_load = true
}

return multi_metering_switch
