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

local devices = {
  BUTTON_PUSH_HELD = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "TRADFRI on/off switch" },
      { mfr = "CentraLite", model = "3450-L" },
      { mfr = "CentraLite", model = "3450-L2" },
    },
    VALUES = {
      supported_button_values = {"pushed", "held"}
    }
  },
  BUTTON_PUSH = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "TRADFRI open/close remote" },
      { mfr = "KE", model = "TRADFRI open/close remote" },
      { mfr = "SOMFY", model = "Situo 1 Zigbee" },
      { mfr = "SOMFY", model = "Situo 4 Zigbee" },
      { mfr = "LDS", model = "ZBT-CCTSwitch-D0001" },
      { mfr = "AduroSmart Eria", model = "ADUROLIGHT_CSC" },
      { mfr = "ADUROLIGHT", model = "ADUROLIGHT_CSC" },
      { mfr = "AduroSmart Eria", model = "Adurolight_NCC" },
      { mfr = "ADUROLIGHT", model = "Adurolight_NCC" },
      { mfr = "HEIMAN", model = "SceneSwitch-EM-3.0" }
    },
    VALUES = {
      supported_button_values = {"pushed"}
    }
  },
  BUTTON_PUSH_HELD_DOUBLE = {
    MATCHING_MATRIX = {
      { mfr = "ShinaSystem", model = "MSM-300Z" },
      { mfr = "ShinaSystem", model = "BSM-300Z" },
      { mfr = "ShinaSystem", model = "SBM300ZB1" },
      { mfr = "ShinaSystem", model = "SBM300ZB2" },
      { mfr = "ShinaSystem", model = "SBM300ZB3" },
    },
    VALUES = {
      supported_button_values = { "pushed", "held", "double" }
    }
  },
}

local configs = {}

configs.get_device_parameters = function(zb_device)
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.MATCHING_MATRIX) do
      if zb_device:get_manufacturer() == fingerprint.mfr and zb_device:get_model() == fingerprint.model then
        return device.VALUES
      end
    end
  end
  return nil
end

return configs
