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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

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
  can_handle = require("using-old-capabilities.yale.yale-bad-battery-reporter.can_handle")
}

return bad_yale_driver
