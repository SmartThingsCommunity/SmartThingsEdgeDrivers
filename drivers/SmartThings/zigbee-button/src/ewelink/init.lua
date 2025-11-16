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

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local OnOff = clusters.OnOff
local button = capabilities.button.button

local EWELINK_BUTTON_FINGERPRINTS = {
  { mfr = "eWeLink", model = "WB01" },
  { mfr = "eWeLink", model = "SNZB-01P" }
}

local function can_handle_ewelink_button(opts, driver, device, ...)
  for _, fingerprint in ipairs(EWELINK_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function do_configure(driver, device)
  device:configure()
  device:send(device_management.build_bind_request(device, OnOff.ID, driver.environment_info.hub_zigbee_eui))
end

local function button_handler(event)
  return function(driver, device, value, zb_rx)
    device:emit_event(event)
  end
end

local ewelink_button = {
  NAME = "eWeLink Button",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = button_handler(button.double({ state_change = true })),
        [OnOff.server.commands.Off.ID] = button_handler(button.held({ state_change = true })),
        [OnOff.server.commands.OffWithEffect.ID] = button_handler(button.pushed({ state_change = true })),
        [OnOff.server.commands.OnWithRecallGlobalScene.ID] = button_handler(button.pushed({ state_change = true })),
        [OnOff.server.commands.OnWithTimedOff.ID] = button_handler(button.pushed({ state_change = true })),
        [OnOff.server.commands.Toggle.ID] = button_handler(button.pushed({ state_change = true }))
      }
    }
  },
  can_handle = can_handle_ewelink_button
}

return ewelink_button