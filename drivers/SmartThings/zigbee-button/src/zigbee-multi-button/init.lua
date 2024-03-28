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
local supported_values = require "zigbee-multi-button.supported_values"

local ZIGBEE_MULTI_BUTTON_FINGERPRINTS = {
  { mfr = "CentraLite", model = "3450-L" },
  { mfr = "CentraLite", model = "3450-L2" },
  { mfr = "AduroSmart Eria", model = "ADUROLIGHT_CSC" },
  { mfr = "ADUROLIGHT", model = "ADUROLIGHT_CSC" },
  { mfr = "AduroSmart Eria", model = "Adurolight_NCC" },
  { mfr = "ADUROLIGHT", model = "Adurolight_NCC" },
  { mfr = "HEIMAN", model = "SceneSwitch-EM-3.0" },
  { mfr = "HEIMAN", model = "HS6SSA-W-EF-3.0" },
  { mfr = "HEIMAN", model = "HS6SSB-W-EF-3.0" },
  { mfr = "IKEA of Sweden", model = "TRADFRI on/off switch" },
  { mfr = "IKEA of Sweden", model = "TRADFRI open/close remote" },
  { mfr = "IKEA of Sweden", model = "TRADFRI remote control" },
  { mfr = "KE", model = "TRADFRI open/close remote" },
  { mfr = "\x02KE", model = "TRADFRI open/close remote" },
  { mfr = "SOMFY", model = "Situo 1 Zigbee" },
  { mfr = "SOMFY", model = "Situo 4 Zigbee" },
  { mfr = "LDS", model = "ZBT-CCTSwitch-D0001" },
  { mfr = "ShinaSystem", model = "MSM-300Z" },
  { mfr = "ShinaSystem", model = "BSM-300Z" },
  { mfr = "ShinaSystem", model = "SBM300ZB1" },
  { mfr = "ShinaSystem", model = "SBM300ZB2" },
  { mfr = "ShinaSystem", model = "SBM300ZB3" },
  { mfr = "ROBB smarrt", model = "ROB_200-007-0" },
  { mfr = "ROBB smarrt", model = "ROB_200-008-0" },
  { mfr = "WALL HERO", model = "ACL-401SCA4" },
  { mfr = "Samsung Electronics", model = "SAMSUNG-ITM-Z-005" }
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
  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    if config ~= nil then
      local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES, { visibility = { displayed = false } }))
      device:emit_component_event(component,
        capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = false } }))
    else
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } }))
      device:emit_component_event(component,
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    end
  end
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
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
    require("zigbee-multi-button.shinasystems"),
    require("zigbee-multi-button.robb"),
    require("zigbee-multi-button.wallhero"),
    require("zigbee-multi-button.SLED")
  }
}

return zigbee_multi_button
