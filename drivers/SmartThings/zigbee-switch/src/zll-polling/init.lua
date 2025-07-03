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

local constants = require "st.zigbee.constants"

-- There are reports of at least one device (SONOFF 01MINIZB) which occasionally
-- reports this value as an Int8, rather than a Boolean, as per the spec
local function zll_profile(opts, driver, device, zb_rx, ...)
  if (device.zigbee_endpoints[device.fingerprinted_endpoint_id].profile == constants.ZLL_PROFILE_ID) then
    local subdriver = require("zll-polling")
    return true, subdriver
  else return false
  end
end

local function set_up_zll_polling(driver, device)
  device.thread:call_on_schedule(5 * 60, function() device:refresh() end, "zll_polling")
end

local ZLL_polling = {
  NAME = "ZLL Polling",
  lifecycle_handlers = {
    init = set_up_zll_polling
  },
  can_handle = zll_profile
}

return ZLL_polling