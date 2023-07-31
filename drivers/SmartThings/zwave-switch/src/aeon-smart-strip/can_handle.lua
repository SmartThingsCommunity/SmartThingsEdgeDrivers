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

local AEON_SMART_STRIP_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0003, model = 0x000B}, -- Aeon Smart Strip DSC11-ZWUS
}

--- Determine whether the passed device is Aeon smart strip
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_aeon_smart_strip(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEON_SMART_STRIP_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver =  require("aeon-smart-strip")
      return true, subdriver
    end
  end
  return false
end

local subdriver = {
  NAME = "Aeon smart strip",
  can_handle = can_handle_aeon_smart_strip
}

return subdriver


