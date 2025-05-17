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
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local device_management = require "st.zigbee.device_management"
local PRESENT_ATTRIBUTE_ID = 0x00fd

local FINGERPRINTS = {
  { mfr = "_TZ3000_ja5osu5g", model = "TS004F"},
  { mfr = "_TZ3000_8rppvwda", model = "TS0041"},
  { mfr = "_TZ3000_pkfazisv", model = "TS0215A"}
}

local function is_tuya_button(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed","held","double"}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
end

local function button_handler(event)
  return function(driver, device, value, zb_rx)
    device:emit_event(event)
  end
end

local tuya_private_cluster_button_handler = function(driver, device, zb_rx)
  local event
  local additional_fields = {
    state_change = true
  }
  local value = string.byte(zb_rx.body.zcl_body.body_bytes, 1)

  if value == 0x00 then
    event = capabilities.button.button.pushed(additional_fields)
  elseif value == 0x01 then
    event = capabilities.button.button.double(additional_fields)
  elseif value == 0x02 then
    event = capabilities.button.button.held(additional_fields)
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

local function do_configure(driver, device)
  device:configure()
  device:send(device_management.build_bind_request(device, OnOff.ID, driver.environment_info.hub_zigbee_eui))
end

local tuya_button_driver = {
  NAME = "tuya button",
  lifecycle_handlers = {
    added = added_handler,
    doConfigure = do_configure
  },
  can_handle = is_tuya_button,
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = button_handler(capabilities.button.button.double({ state_change = true })),
        [OnOff.server.commands.Off.ID] = button_handler(capabilities.button.button.held({ state_change = true })),
        [OnOff.server.commands.Toggle.ID] = button_handler(capabilities.button.button.pushed({ state_change = true })),
        [PRESENT_ATTRIBUTE_ID] = tuya_private_cluster_button_handler
      }
    }
  },
  sub_drivers = {
    require("button.meian-button")
  }
}

return tuya_button_driver
