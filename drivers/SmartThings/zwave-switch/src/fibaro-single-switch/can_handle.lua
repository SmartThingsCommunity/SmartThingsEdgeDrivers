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


local fibaro_single_switch = {
  NAME = "fibaro single switch",
  can_handle = can_handle_fibaro_single_switch,
  lazy_load = true
}

return fibaro_single_switch
