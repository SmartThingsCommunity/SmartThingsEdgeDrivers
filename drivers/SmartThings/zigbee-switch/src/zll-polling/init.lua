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

local device_lib = require "st.device"
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"

local function zll_profile(opts, driver, device, zb_rx, ...)
  local endpoint = device.zigbee_endpoints ~= nil and
    (device.zigbee_endpoints[device.fingerprinted_endpoint_id] or device.zigbee_endpoints[tostring(device.fingerprinted_endpoint_id)])
  if (endpoint ~= nil and endpoint.profile_id == constants.ZLL_PROFILE_ID) then
    local subdriver = require("zll-polling")
    return true, subdriver
  else
    return false
  end
end

local function set_up_zll_polling(driver, device)
  local INFREQUENT_POLL_COUNTER = "_infrequent_poll_counter"
  local function poll()
    local infrequent_counter = device:get_field(INFREQUENT_POLL_COUNTER) or 1
    if infrequent_counter == 12 then
      -- do a full refresh once an hour
      device:refresh()
      infrequent_counter = 0
    else
      -- Read On/Off every poll
      for _, ep in pairs(device.zigbee_endpoints) do
        if device:supports_server_cluster(clusters.OnOff.ID, ep.id) then
          device:send(clusters.OnOff.attributes.OnOff:read(device):to_endpoint(ep.id))
        end
      end
      infrequent_counter = infrequent_counter + 1
    end
    device:set_field(INFREQUENT_POLL_COUNTER, infrequent_counter)
  end

  -- only set this up for non-child devices
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device.thread:call_on_schedule(5 * 60, poll, "zll_polling")
  end
end

local ZLL_polling = {
  NAME = "ZLL Polling",
  lifecycle_handlers = {
    init = set_up_zll_polling
  },
  can_handle = zll_profile
}

return ZLL_polling