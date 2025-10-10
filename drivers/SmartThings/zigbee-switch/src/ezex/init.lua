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
local configurations = require "configurations"

local do_init = function(self, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000000, {persist = true})
  device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1000, {persist = true})
end

local ezex_switch_handler = {
  NAME = "ezex switch handler",
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(do_init)
  },
  can_handle = require("ezex.can_handle"),
}

return ezex_switch_handler
