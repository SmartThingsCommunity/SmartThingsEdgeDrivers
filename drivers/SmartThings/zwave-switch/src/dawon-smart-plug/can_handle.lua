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

local DAWON_SMART_PLUG_FINGERPRINTS = {
  {mfr = 0x018C, prod = 0x0042, model = 0x0005}, -- Dawon Smart Plug
  {mfr = 0x018C, prod = 0x0042, model = 0x0008} -- Dawon Smart Multitab
}

--- Determine whether the passed device is Dawon smart plug
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_dawon_smart_plug(opts, driver, device, ...)
  for _, fingerprint in ipairs(DAWON_SMART_PLUG_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("dawon-smart-plug")
      return true, subdriver
    end
  end
  return false
end

local dawon_smart_plug = {
  NAME = "Dawon smart plug",
  can_handle = can_handle_dawon_smart_plug,
  lazy_load = true
}

return dawon_smart_plug
