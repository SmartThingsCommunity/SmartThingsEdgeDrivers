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

local devices = {
  EVERSPRING_PIR = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = 0x0001,
      product_ids = 0x0004
    },
    PARAMETERS = {
      temperatureAndHumidityReport = {parameter_number = 1, size = 2},
      retriggerIntervalSetting = {parameter_number = 2, size = 2}
    }
  },
  FIBARO_FLOOD_SENSOR_ZW5 = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0B01,
      product_ids = {0x1002, 0x1003, 0x2002}
    },
    PARAMETERS = {
      alarmCancellationDelay = {parameter_number = 1, size = 2},
      acousticVisualSignals = {parameter_number = 2, size = 1},
      tempMeasurementInterval = {parameter_number = 10, size = 4},
      floodSensorTurnedOnOff = {parameter_number = 77, size = 1}
    }
  },
  FIBARO_DOOR_WINDOW_SENSOR_WITH_TEMPERATURE = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0701,
      product_ids = 0x2001
    },
    PARAMETERS = {
      alarmStatus = {parameter_number = 2, size = 1},
      visualLedIndications = {parameter_number = 3, size = 1},
      delayOfTamperAlarmCancel = {parameter_number = 30, size = 2},
      reportTamperAlarmCancel = {parameter_number = 31, size = 1},
      tempMeasurementInterval = {parameter_number = 50, size = 2},
      tempReportsThreshold = {parameter_number = 51, size = 2},
      intervalOfTempReports = {parameter_number = 52, size = 2},
      temperatureOffset = {parameter_number = 53, size = 4},
      temperatureAlarmReports = {parameter_number = 54, size = 1},
      highTempThreshold = {parameter_number = 55, size = 2},
      lowTempThreshold = {parameter_number = 56, size = 2}
    }
  },
  EZMULTIPLI = {
    MATCHING_MATRIX = {
        mfrs = 0x001E,
        product_types = 0x0004,
        product_ids = 0x0001
    },
    PARAMETERS = {
      onTime = {parameter_number = 1, size = 1},
      onLevel = {parameter_number = 2, size = 1},
      liteMin = {parameter_number = 3, size = 1},
      tempMin = {parameter_number = 4, size = 1},
      tempAdj = {parameter_number = 5, size = 1}
    }
  },
  FIBARO_DOOR_WINDOW_SENSOR_2 = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0702,
      product_ids = {0x1000, 0x2000, 0x3000}
    },
    PARAMETERS = {
      doorWindowState = {parameter_number = 1, size = 1},
      visualLedIndications = {parameter_number = 2, size = 1},
      tamperCancelDelay = {parameter_number = 30, size = 2},
      cancelTamperReport = {parameter_number = 31, size = 1},
      tempMeasurementInterval = {parameter_number = 50, size = 2},
      tempReportsThreshold = {parameter_number = 51, size = 2},
      temperatureAlarmReports = {parameter_number = 54, size = 1},
      highTempThreshold = {parameter_number = 55, size = 2},
      lowTempThreshold = {parameter_number = 56, size = 2}
    }
  },
  ZOOZ_4_IN_1_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x027A,
      product_types = 0x2021,
      product_ids = 0x2101
    },
    PARAMETERS = {
      temperatureScale = {parameter_number = 1, size = 1},
      temperatureChange = {parameter_number = 2, size = 1},
      humidityChange = {parameter_number = 3, size = 1},
      illuminanceChange = {parameter_number = 4, size = 1},
      motionInterval = {parameter_number = 5, size = 1},
      motionSensitivity = {parameter_number = 6, size = 1},
      ledMode = {parameter_number = 7, size = 1}
    }
  }
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
