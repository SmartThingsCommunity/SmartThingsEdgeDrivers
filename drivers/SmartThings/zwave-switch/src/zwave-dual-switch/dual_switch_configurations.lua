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
  FIBARO_WALLI_DOUBLE_SWITCH = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x1B01,
      product_ids = 0x1000
    },
    DUAL_SWITCH_CONFIGURATION = {
      child_switch_device_profile = "metering-switch"
    }
  },
  ZWAVE_DOUBLE_PLUG = {
    MATCHING_MATRIX = {
      mfrs = 0x027A,
      product_types = 0xA000,
      product_ids = 0xA003
    },
    DUAL_SWITCH_CONFIGURATION = {
      child_switch_device_profile = "metering-switch"
    }
  }
}

local dual_switch_configurations = {}

dual_switch_configurations.get_child_device_configuration = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.DUAL_SWITCH_CONFIGURATION
    end
  end
  return {
    child_switch_device_profile = "switch-binary"
  }
end

return dual_switch_configurations
