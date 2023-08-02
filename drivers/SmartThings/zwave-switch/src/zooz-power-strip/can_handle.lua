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

local ZOOZ_POWER_STRIP_FINGERPRINTS = {
  {mfr = 0x015D, prod = 0x0651, model = 0xF51C} -- Zooz ZEN 20 Power Strip
}

local function can_handle_zooz_power_strip(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZOOZ_POWER_STRIP_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zooz-power-strip")
      return true, subdriver
    end
  end
  return false
end

local zooz_power_strip = {
  NAME = "zooz power strip",
  can_handle = can_handle_zooz_power_strip,
}

return zooz_power_strip
