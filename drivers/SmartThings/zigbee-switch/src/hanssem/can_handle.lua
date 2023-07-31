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

local FINGERPRINTS = {
  { mfr = "Winners", model = "LSS1-101", children = 0 },
  { mfr = "Winners", model = "LSS1-102", children = 1 },
  { mfr = "Winners", model = "LSS1-103", children = 2 },
  { mfr = "Winners", model = "LSS1-204", children = 3 },
  { mfr = "Winners", model = "LSS1-205", children = 4 },
  { mfr = "Winners", model = "LSS1-206", children = 5 }
}

local function can_handle_hanssem_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("hanssem")
      return true, subdriver
    end
  end
  return false
end

local HanssemSwitch = {
  NAME = "Zigbee Hanssem Switch",
  can_handle = can_handle_hanssem_switch
}

return HanssemSwitch