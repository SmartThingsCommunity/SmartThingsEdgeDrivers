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
  PHILIO_SOUND_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x013C,
      product_types = 0x0004,
      product_ids = 0x000A
    },
    PARAMETERS = {
      duration = {parameter_number = 31, size = 1}
    }
  },
  AEOTEC_DOORBELL_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x371,
      product_types = {0x0003, 0x0103, 0x0203},
      product_ids = {0x00A2, 0x00A4}
    },
    PARAMETERS = {
      buttonUnpairingMode = {parameter_number = 48, size = 1},
      buttonPairingMode = {parameter_number = 49, size = 1},
    }
  },
  YALE_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x0129,
      product_types = 0x6F01,
      product_ids = 0x0001
    },
    PARAMETERS = {
      ["certifiedpreferences.alarmLength"] = {parameter_number = 1, size = 1},
      ["certifiedpreferences.alarmLEDflash"] = {parameter_number = 2, size = 1},
      ["certifiedpreferences.comfortLED"] = {parameter_number = 3, size = 1},
      ["certifiedpreferences.tamper"] = {parameter_number = 4, size = 1},
    }
  },
  EVERSPRING_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = 0x000C,
      product_ids = 0x0002
    },
    PARAMETERS = {
      alarmLength = {parameter_number = 1, size = 2}
    }
  },
  ZOOZ_ZSE50_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x027A,
      product_types = 0x0004,
      product_ids = 0x0369
    },
    PARAMETERS = {
      playbackMode = { parameter_number = 1, size = 1 },
      playbackDuration = { parameter_number = 2, size = 2 },
      playbackLoop = { parameter_number = 3, size = 1 },
      playbackTone = { parameter_number = 4, size = 1 },
      playbackVolume = { parameter_number = 5, size = 1 },
      ledMode = { parameter_number = 6, size = 1 },
      ledColor = { parameter_number = 7, size = 1 },
      lowBattery = { parameter_number = 8, size = 1 },
      ledBatteryMode = { parameter_number = 9, size = 1 },
      btnToneSelection = { parameter_number = 10, size = 1 },
      btnVolSelection = { parameter_number = 11, size = 1 },
      basicSetGrp2 = { parameter_number = 12, size = 1 }, --Not Used
      systemVolume = { parameter_number = 13, size = 1 },
      ledBrightness = { parameter_number = 14, size = 1 },
      batteryFrequency = { parameter_number = 15, size = 1 },
      batteryThreshold = { parameter_number = 16, size = 1 }
    }
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
