-- Copyright 2021 SmartThings
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
local supported_values = require "zigbee-multi-button.supported_values"

local ZIGBEE_MULTI_BUTTON_FINGERPRINTS = {
  { mfr = "CentraLite", model = "3450-L" },
  { mfr = "CentraLite", model = "3450-L2" },
  { mfr = "AduroSmart Eria", model = "ADUROLIGHT_CSC" },
  { mfr = "ADUROLIGHT", model = "ADUROLIGHT_CSC" },
  { mfr = "AduroSmart Eria", model = "Adurolight_NCC" },
  { mfr = "ADUROLIGHT", model = "Adurolight_NCC" },
  { mfr = "HEIMAN", model = "SceneSwitch-EM-3.0" },
  { mfr = "IKEA of Sweden", model = "TRADFRI on/off switch" },
  { mfr = "IKEA of Sweden", model = "TRADFRI open/close remote" },
  { mfr = "IKEA of Sweden", model = "TRADFRI remote control" },
  { mfr = "KE", model = "TRADFRI open/close remote" },
  { mfr = "SOMFY", model = "Situo 1 Zigbee" },
  { mfr = "SOMFY", model = "Situo 4 Zigbee" },
  { mfr = "LDS", model = "ZBT-CCTSwitch-D0001" },
  { mfr = "ShinaSystem", model = "MSM-300Z" },
  { mfr = "ShinaSystem", model = "BSM-300Z" },
  { mfr = "ShinaSystem", model = "SBM300ZB1" },
  { mfr = "ShinaSystem", model = "SBM300ZB2" },
  { mfr = "ShinaSystem", model = "SBM300ZB3" }
}

local function can_handle_zigbee_multi_button(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZIGBEE_MULTI_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function added_handler(self, device)
  local sv = supported_values.get_device_parameters(device)
  for comp_name, comp in pairs(device.profile.components) do
    if comp_name ~= "main" then
      if sv ~= nil then
        device:emit_component_event(comp, capabilities.button.supportedButtonValues(sv.supported_button_values))
      else
        device:emit_component_event(comp, capabilities.button.supportedButtonValues({"pushed", "held"}))
      end
      device:emit_component_event(comp, capabilities.button.numberOfButtons({value = 1}))
    end
  end
end

local zigbee_multi_button = {
  NAME = "ZigBee multi button",
  lifecycle_handlers = {
    added = added_handler
  },
  can_handle = can_handle_zigbee_multi_button,
  sub_drivers = {
    require("zigbee-multi-button.ikea"),
    require("zigbee-multi-button.somfy"),
    require("zigbee-multi-button.ecosmart"),
    require("zigbee-multi-button.centralite"),
    require("zigbee-multi-button.adurosmart"),
    require("zigbee-multi-button.heiman"),
    require("zigbee-multi-button.shinasystems")
  }
}

return zigbee_multi_button
