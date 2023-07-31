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

local EATON_ACCESSORY_DIMMER_FINGERPRINTS = {
  {mfr = 0x001A, prod = 0x4441, model = 0x0000} -- Eaton Dimmer Switch
}

local function can_handle_eaton_accessory_dimmer(opts, driver, device, ...)
  for _, fingerprint in ipairs(EATON_ACCESSORY_DIMMER_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("eaton-accessory-dimmer")
      return true, subdriver
    end
  end
  return false
end

local subdriver = {
  NAME = "eaton accessory dimmer",
  can_handle = can_handle_eaton_accessory_dimmer
}

return subdriver
