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

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local devices = {
  AQARA_LIGHT = {
    MATCHING_MATRIX = { mfr = "LUMI", model = "lumi.light.acn004" },
    PARAMETERS = {
      ["stse.restorePowerState"] = function(device, value)
        return cluster_base.write_manufacturer_specific_attribute(device, 0xFCC0,
          0x0201, 0x115F, data_types.Boolean, value)
      end,
      ["stse.turnOffIndicatorLight"] = function(device, value)
        return cluster_base.write_manufacturer_specific_attribute(device, 0xFCC0,
          0x0203, 0x115F, data_types.Boolean, value)
      end,
      ["stse.lightFadeInTimeInSec"] = function(device, value)
        local raw_value = value * 10 -- value unit: 1sec, transition time unit: 100ms
        return clusters.Level.attributes.OnTransitionTime:write(device, raw_value)
      end,
      ["stse.lightFadeOutTimeInSec"] = function(device, value)
        local raw_value = value * 10 -- value unit: 1sec, transition time unit: 100ms
        return clusters.Level.attributes.OffTransitionTime:write(device, raw_value)
      end
    }
  },
  AQARA_LIGHT_BULB = {
    MATCHING_MATRIX = { mfr = "Aqara", model = "lumi.light.acn014" },
    PARAMETERS = {
      ["stse.restorePowerState"] = function(device, value)
        return cluster_base.write_manufacturer_specific_attribute(device, 0xFCC0,
          0x0201, 0x115F, data_types.Boolean, value)
      end
    }
  }
}
local preferences = {}

preferences.update_preferences = function(driver, device, args)
  local prefs = preferences.get_device_parameters(device)
  if prefs ~= nil then
    for id, value in pairs(device.preferences) do
      if not (args and args.old_st_store) or (args.old_st_store.preferences[id] ~= value and prefs and prefs[id]) then
        local message = prefs[id](device, value)
        device:send(message)
      end
    end
  end
end

preferences.get_device_parameters = function(zigbee_device)
  for _, device in pairs(devices) do
    if zigbee_device:get_manufacturer() == device.MATCHING_MATRIX.mfr and
        zigbee_device:get_model() == device.MATCHING_MATRIX.model then
      return device.PARAMETERS
    end
  end
  return nil
end

return preferences
