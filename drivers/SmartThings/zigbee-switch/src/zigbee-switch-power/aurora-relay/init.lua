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

local constants = require "st.zigbee.constants"

local AURORA_RELAY_FINGERPRINTS = {
  { mfr = "Aurora", model = "Smart16ARelay51AU" },
  { mfr = "Develco Products A/S", model = "Smart16ARelay51AU" },
  { mfr = "SALUS", model = "SX885ZB" }
}

local function can_handle_aurora_relay(opts, driver, device)
  for _, fingerprint in ipairs(AURORA_RELAY_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function do_configure(driver, device)
  device:configure()

  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1, {persist = true})

  device:refresh()
end

local aurora_relay = {
  NAME = "Aurora Relay/SALUS",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_aurora_relay
}

return aurora_relay
