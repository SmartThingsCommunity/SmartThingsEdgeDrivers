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
  QUBINO = {
    MATCHING_MATRIX = {
      mfrs = 0x0159,
      product_types = 0x0003,
      product_ids = {0x0052, 0x0053}
    },
    PARAMETERS = {
      operatingModes =          {parameter_number = 71, size = 1},
      slatsTurnTime =           {parameter_number = 72, size = 2},
      slatsPosition =           {parameter_number = 73, size = 1},
      motorUpDownTime =         {parameter_number = 74, size = 2},
      motorOperationDetection = {parameter_number = 76, size = 1},
      forcedCalibration =       {parameter_number = 78, size = 1}
    }
  },

  FIBARO = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x1D01,
      product_ids = 0x1000,
    },
    PARAMETERS = {
      ledFrameWhenMoving =        {parameter_number = 11, size = 1},
      ledFrameWhenNotMoving =     {parameter_number = 12, size = 1},
      ledFrameBrightness =        {parameter_number = 13, size = 1},
      calibration =               {parameter_number = 150, size = 1},
      operatingMode =             {parameter_number = 151, size = 1},
      venetianBlindTurnTime =     {parameter_number = 152, size = 4},
      delayAtEndSwitch =          {parameter_number = 154, size = 2},
      motorEndMoveDetection =     {parameter_number = 155, size = 2},
      buttonsOrientation =        {parameter_number = 24, size = 1},
      outputsOrientation =        {parameter_number = 25, size = 1},
      powerWithSelfConsumption =  {parameter_number = 60, size = 1},
      powerReportsOnChange =      {parameter_number = 61, size = 2},
      powerReportsPeriodic =      {parameter_number = 62, size = 2},
      energyReportsOnChange =     {parameter_number = 65, size = 2},
      energyReportsPeriodic =     {parameter_number = 66, size = 2}
    }
  },
  IBLINDS_V3 = {
    MATCHING_MATRIX = {
      mfrs = 0x0287,
      product_types = 0x0004,
      product_ids = {0x0071, 0x0072}
    },
    PARAMETERS = {
      closeInterval = {parameter_number = 1, size = 1},
      reverse = {parameter_number = 2, size = 1},
      forceReport = {parameter_number = 3, size = 1},
      defaultOnValue = {parameter_number = 4, size = 1},
      disableResetButton = {parameter_number = 5, size = 1},
      openCloseSpeed = {parameter_number = 6, size = 1},
      remoteCalibration = {parameter_number = 7, size = 1},
      minTilt = {parameter_number = 8, size = 1},
      maxTilt = {parameter_number = 9, size = 1},
      remap = {parameter_number = 10, size = 1}
    }
  },
  AEON_NANO_SHUTTER = {
    MATCHING_MATRIX = {
      mfrs = {0x0086, 0x0371},
      product_types = {0x0003, 0x0103},
      product_ids = 0x008D
    },
    PARAMETERS = {
      openCloseTiming = {parameter_number = 35, size = 1}
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
