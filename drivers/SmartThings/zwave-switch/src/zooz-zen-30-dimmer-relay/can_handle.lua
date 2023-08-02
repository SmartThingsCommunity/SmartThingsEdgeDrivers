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

local ZOOZ_ZEN_30_DIMMER_RELAY_FINGERPRINTS = {
  { mfr = 0x027A, prod = 0xA000, model = 0xA008 } -- Zooz Zen 30 Dimmer Relay Double Switch
}

local function can_handle_zooz_zen_30_dimmer_relay_double_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZOOZ_ZEN_30_DIMMER_RELAY_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zooz-zen-30-dimmer-relay")
      return true, subdriver
    end
  end
  return false
end

local zooz_zen_30_dimmer_relay_double_switch = {
  NAME = "Zooz Zen 30",
  can_handle = can_handle_zooz_zen_30_dimmer_relay_double_switch
}

return zooz_zen_30_dimmer_relay_double_switch
