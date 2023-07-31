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
local ECOLINK_FINGERPRINTS = {
  {mfr = 0x014A, prod = 0x0006, model = 0x0002},
  {mfr = 0x014A, prod = 0x0006, model = 0x0003},
  {mfr = 0x014A, prod = 0x0006, model = 0x0004},
  {mfr = 0x014A, prod = 0x0006, model = 0x0005},
  {mfr = 0x014A, prod = 0x0006, model = 0x0006}
}

local function can_handle_ecolink(opts, driver, device, ...)
  for _, fingerprint in ipairs(ECOLINK_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("ecolink-switch")
      return true, subdriver
    end
  end
  return false
end

local ecolink_switch = {
  NAME = "Ecolink Switch",
  can_handle = can_handle_ecolink,
  lazy_load = true
}

return ecolink_switch
