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
  DAWON_WALL_SMART_SWITCH_KR_1 = {
    MATCHING_MATRIX = {
      mfrs = 0x018C,
      product_types = 0x0061,
      product_ids = 0x0001,
      children = 1      
    },
    CONFIGURATION = {
      child_switch_device_profile = "child-switch"
    }
  },
  DAWON_WALL_SMART_SWITCH_KR_2 = {
    MATCHING_MATRIX = {
      mfrs = 0x018C,
      product_types = 0x0062,
      product_ids = 0x0001,
      children = 2
    },
    CONFIGURATION = {
      child_switch_device_profile = "child-switch"
    }
  },
  DAWON_WALL_SMART_SWITCH_KR_3 = {
    MATCHING_MATRIX = {
      mfrs = 0x018C,
      product_types = 0x0063,
      product_ids = 0x0001,
      children = 3
    },
    CONFIGURATION = {
      child_switch_device_profile = "child-switch"
    }
  },
  DAWON_WALL_SMART_SWITCH_US_1 = {
    MATCHING_MATRIX = {
      mfrs = 0x018C,
      product_types = 0x0064,
      product_ids = 0x0001,
      children = 1
    },
    CONFIGURATION = {
      child_switch_device_profile = "child-switch"
    }
  },
  DAWON_WALL_SMART_SWITCH_US_2 = {
    MATCHING_MATRIX = {
      mfrs = 0x018C,
      product_types = 0x0065,
      product_ids = 0x0001,
      children = 2
    },
    CONFIGURATION = {
      child_switch_device_profile = "child-switch"
    }
  },
  DAWON_WALL_SMART_SWITCH_US_3 = {
    MATCHING_MATRIX = {
      mfrs = 0x018C,
      product_types = 0x0066,
      product_ids = 0x0001,
      children = 3
    },
    CONFIGURATION = {
      child_switch_device_profile = "child-switch"
    }
  }
}

local dawon_wall_smart_switch_configurations = {}

dawon_wall_smart_switch_configurations.get_child_switch_device_profile = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.CONFIGURATION.child_switch_device_profile
    end
  end
end

dawon_wall_smart_switch_configurations.get_child_amount = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.MATCHING_MATRIX.children
    end
  end
end

return dawon_wall_smart_switch_configurations
