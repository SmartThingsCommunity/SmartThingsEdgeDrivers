-- Copyright 2025 SmartThings
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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local BAD_YALE_LOCK_FINGERPRINTS = {
  { mfr = "Yale", model = "YRD220/240 TSDB" },
  { mfr = "Yale", model = "YRL220 TS LL" },
  { mfr = "Yale", model = "YRD210 PB DB" },
  { mfr = "Yale", model = "YRL210 PB LL" },
  { mfr = "ASSA ABLOY iRevo", model = "c700000202" },
  { mfr = "ASSA ABLOY iRevo", model = "06ffff2027" }
}

local is_bad_yale_lock_models = function(opts, driver, device)
  for _, fingerprint in ipairs(BAD_YALE_LOCK_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local battery_report_handler = function(driver, device, value)
   device:emit_event(capabilities.battery.battery(value.value))
end

local bad_yale_driver = {
  NAME = "YALE BAD Lock Driver",
  zigbee_handlers = {
    attr = {
      [clusters.PowerConfiguration.ID] = {
        [clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_report_handler
      }
    }
  },
  can_handle =  is_bad_yale_lock_models
}

return bad_yale_driver
