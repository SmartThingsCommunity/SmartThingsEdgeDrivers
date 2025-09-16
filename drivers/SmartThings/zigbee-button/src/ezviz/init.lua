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

local capabilities = require "st.capabilities"

local EZVIZ_PRIVATE_BUTTON_CLUSTER = 0xFE05
local EZVIZ_PRIVATE_STANDARD_CLUSTER = 0xFE00
local EZVIZ_PRIVATE_BUTTON_ATTRIBUTE = 0x0000
local EZVIZ_MFR = "EZVIZ"

local is_ezviz_button = function(opts, driver, device)
  local support_button_cluster = device:supports_server_cluster(EZVIZ_PRIVATE_BUTTON_CLUSTER)
  local support_standard_cluster = device:supports_server_cluster(EZVIZ_PRIVATE_STANDARD_CLUSTER)
  if device:get_manufacturer() == EZVIZ_MFR and support_button_cluster and support_standard_cluster then
    return true
  end
end

local ezviz_private_cluster_button_handler = function(driver, device, zb_rx)
  local event
  local additional_fields = {
    state_change = true
  }
  if zb_rx.value == 0x01 then
    event = capabilities.button.button.pushed(additional_fields)
  elseif zb_rx.value == 0x02 then
    event = capabilities.button.button.double(additional_fields)
  elseif zb_rx.value == 0x03 then
    event = capabilities.button.button.held(additional_fields)
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

local ezviz_button_handler = {
  NAME = "Ezviz Button",
  zigbee_handlers = {
    attr = {
      [EZVIZ_PRIVATE_BUTTON_CLUSTER] = {
        [EZVIZ_PRIVATE_BUTTON_ATTRIBUTE] = ezviz_private_cluster_button_handler
      }
    }
  },
  can_handle = is_ezviz_button
}
return ezviz_button_handler