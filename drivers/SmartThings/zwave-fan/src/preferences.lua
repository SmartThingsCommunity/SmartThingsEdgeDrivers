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
    LEVITON = {
      MATCHING_MATRIX = {  -- Zwave 4 speed fan controller model ZW4SF
        mfrs = 0x001D,
        product_types = 0x0038,
        product_ids   = 0x0002,
      },
      PARAMETERS = {
        minimumFanSpeedLevel =          {parameter_number = 3, size = 1},  -- P3: Minimum fan speed level
        maximumFanSpeedLevel =          {parameter_number = 4, size = 1},  -- P4: Maximum fan speed level
        presetFanSpeedLevel  =          {parameter_number = 5, size = 1},  -- P5: Preset fan speed level
        ledLevelIndicatorTimeout =      {parameter_number = 6, size = 1},  -- P6: LED level indicator timeout 
        statusLEDConfiguration =        {parameter_number = 7, size = 1},  -- P7: Status LED configuration 
      },
    },
  }
  
  local preferences = {}
  
  preferences.get_device_parameters = function(zw_device)
      for _, device in pairs(devices) do
          if zw_device:id_match(
              device.MATCHING_MATRIX.mfrs,
              device.MATCHING_MATRIX.product_types,
              device.MATCHING_MATRIX.product_ids) then
              return device.PARAMETERS
          end
      end
      return nil
  end
  
  preferences.to_numeric_value = function(new_value)
    local numeric = tonumber(new_value)
    if numeric == nil then -- in case the value is boolean
      numeric = new_value and 1 or 0
    end
    return numeric
  end
  
  return preferences
