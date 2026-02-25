-- Copyright 2026 SmartThings
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

local capabilities = require "st.capabilities"
local log = require "log"

local SONOFF_CLUSTER_ID = 0xFC12
local SONOFF_ATTR_ID = 0x0000

local EVENT_MAP = {
  [0x01] = capabilities.button.button.pushed,
  [0x02] = capabilities.button.button.double,
  [0x03] = capabilities.button.button.held,
  [0x04] = capabilities.button.button.pushed_3x
}

local function can_handle(opts, driver, device, ...)
  return device:get_manufacturer() == "SONOFF"
end

local function sonoff_attr_handler(driver, device, value, zb_rx)
  local attr_val = value.value
  local endpoint = zb_rx.address_header.src_endpoint.value
  local button_name = "button" .. tostring(endpoint)
  local event_func = EVENT_MAP[attr_val]
  if event_func then
    local comp = device.profile.components[button_name]
    if comp then
        device:emit_component_event(comp, event_func({state_change = true}))
    else
      log.warn("Unknown button component: " .. button_name)
    end
  else
    log.warn("Unknown event value: " .. tostring(attr_val))
  end
end

local sonoff_handler = {
  NAME = "SONOFF Multi-Button Handler",
  zigbee_handlers = {
    attr = {
      [SONOFF_CLUSTER_ID] = {
        [SONOFF_ATTR_ID] = sonoff_attr_handler
      }
    }
  },
  can_handle = can_handle
}

return sonoff_handler
