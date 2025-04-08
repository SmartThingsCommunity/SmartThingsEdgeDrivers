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
local defaults = require "st.zigbee.defaults"

local EZVIZ_PRIVATE_CLUSTER = 0xFE05
local EZVIZ_PRIVATE_ATTRIBUTE = 0x0000

local EZVIZ_MFR = "EZVIZ"

local is_ezviz_button = function(opts, driver, device)
  if device:supports_capability(capabilities.button) and device:get_manufacturer() == EZVIZ_MFR then
    return true
  end
end

-- We need an empty added here to override the added in root init.lua, because we already knows its profile
local device_added = function(self, device)
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
  supported_capabilities = {
    capabilities.battery,
    capabilities.button,
    capabilities.refresh
  },
  zigbee_handlers = {
    attr = {
      [EZVIZ_PRIVATE_CLUSTER] = {
        [EZVIZ_PRIVATE_ATTRIBUTE] = ezviz_private_cluster_button_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = is_ezviz_button
}
defaults.register_for_default_handlers(ezviz_button_handler, ezviz_button_handler.supported_capabilities)
return ezviz_button_handler