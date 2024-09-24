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

local zigbee_constants = require "st.zigbee.constants"

local ZIGBEE_METERING_SWITCH_FINGERPRINTS = {
  { model = "E240-KR116Z-HA" }
}

local is_zigbee_ezex_switch = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_METERING_SWITCH_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      local subdriver = require("ezex")
      return true, subdriver
    end
  end

  return false
end

local do_init = function(self, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000000, {persist = true})
  device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1000, {persist = true})
end

local ezex_switch_handler = {
  NAME = "ezex switch handler",
  lifecycle_handlers = {
    init = do_init
  },
  can_handle = is_zigbee_ezex_switch
}

return ezex_switch_handler
