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
  BUTTON_PUSH_HELD_2 = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "TRADFRI on/off switch" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held" },
    NUMBER_OF_BUTTONS = 2
  },
  BUTTON_PUSH_HELD_4 = {
    MATCHING_MATRIX = {
      { mfr = "CentraLite", model = "3450-L" },
      { mfr = "CentraLite", model = "3450-L2" },
      { mfr = "ROBB smarrt", model = "ROB_200-008-0" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held" },
    NUMBER_OF_BUTTONS = 4
  },
  BUTTON_PUSH_HELD_8 = {
    MATCHING_MATRIX = {
      { mfr = "ROBB smarrt", model = "ROB_200-007-0" },
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held" },
    NUMBER_OF_BUTTONS = 8
  },
  BUTTON_PUSH_2 = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "TRADFRI open/close remote" },
      { mfr = "KE", model = "TRADFRI open/close remote" },
      { mfr = "\x02KE", model = "TRADFRI open/close remote" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed" },
    NUMBER_OF_BUTTONS = 2
  },
  BUTTON_PUSH_3 = {
    MATCHING_MATRIX = {
      { mfr = "SOMFY", model = "Situo 1 Zigbee" },
      { mfr = "HEIMAN", model = "HS6SSB-W-EF-3.0" },
    },
    SUPPORTED_BUTTON_VALUES = { "pushed" },
    NUMBER_OF_BUTTONS = 3
  },
  BUTTON_PUSH_HELD_3 = {
    MATCHING_MATRIX = {
      { mfr = "Samsung Electronics", model = "SAMSUNG-ITM-Z-005" },
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held" },
    NUMBER_OF_BUTTONS = 3
  },
  BUTTON_PUSH_4 = {
    MATCHING_MATRIX = {
      { mfr = "LDS", model = "ZBT-CCTSwitch-D0001" },
      { mfr = "AduroSmart Eria", model = "ADUROLIGHT_CSC" },
      { mfr = "ADUROLIGHT", model = "ADUROLIGHT_CSC" },
      { mfr = "AduroSmart Eria", model = "Adurolight_NCC" },
      { mfr = "ADUROLIGHT", model = "Adurolight_NCC" },
      { mfr = "HEIMAN", model = "SceneSwitch-EM-3.0" },
      { mfr = "HEIMAN", model = "HS6SSA-W-EF-3.0" },
    },
    SUPPORTED_BUTTON_VALUES = { "pushed" },
    NUMBER_OF_BUTTONS = 4
  },
  BUTTON_PUSH_12 = {
    MATCHING_MATRIX = {
      { mfr = "SOMFY", model = "Situo 4 Zigbee" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed" },
    NUMBER_OF_BUTTONS = 12
  },
  BUTTON_PUSH_30 = {
    MATCHING_MATRIX = {
      { mfr = "WALL HERO", model = "ACL-401SCA4" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed" },
    NUMBER_OF_BUTTONS = 30
  },
  BUTTON_PUSH_HELD_DOUBLE_1 = {
    MATCHING_MATRIX = {
      { mfr = "ShinaSystem", model = "BSM-300Z" },
      { mfr = "ShinaSystem", model = "SBM300ZB1" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held", "double" },
    NUMBER_OF_BUTTONS = 1
  },
  BUTTON_PUSH_HELD_DOUBLE_2 = {
    MATCHING_MATRIX = {
      { mfr = "ShinaSystem", model = "SBM300ZB2" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held", "double" },
    NUMBER_OF_BUTTONS = 2
  },
  BUTTON_PUSH_HELD_DOUBLE_3 = {
    MATCHING_MATRIX = {
      { mfr = "ShinaSystem", model = "SBM300ZB3" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held", "double" },
    NUMBER_OF_BUTTONS = 3
  },
  BUTTON_PUSH_HELD_DOUBLE_4 = {
    MATCHING_MATRIX = {
      { mfr = "ShinaSystem", model = "MSM-300Z" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held", "double" },
    NUMBER_OF_BUTTONS = 4
  }
}

local configs = {}

configs.get_device_parameters = function(zb_device)
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.MATCHING_MATRIX) do
      if zb_device:get_manufacturer() == fingerprint.mfr and zb_device:get_model() == fingerprint.model then
        return device
      end
    end
  end
  return nil
end

return configs
