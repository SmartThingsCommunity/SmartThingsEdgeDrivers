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

local ZIGBEE_POWER_METER_FINGERPRINTS = {
  { model = "ZHEMI101" },
  { model = "EMIZB-132" },
}

local is_frient_power_meter = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_POWER_METER_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true
    end
  end

  return false
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()
end

local device_init = function(self, device)
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10000, {persist = true})
end

local frient_power_meter_handler = {
  NAME = "frient power meter handler",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
  },
  can_handle = is_frient_power_meter
}

return frient_power_meter_handler