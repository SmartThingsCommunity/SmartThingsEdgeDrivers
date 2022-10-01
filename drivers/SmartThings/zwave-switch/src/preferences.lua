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
  INOVELLI = {
    MATCHING_MATRIX = {
      mfrs = 0x031E,
      product_types = {0x0001, 0x0003},
      product_ids = 0x0001
    },
    PARAMETERS = {
      dimmingSpeed = {parameter_number = 1, size = 1},
      dimmingSpeedZWave = {parameter_number = 2, size = 1},
      rampRate = {parameter_number = 3, size = 1},
      rampRateZWave = {parameter_number = 4, size = 1},
      minimumDimLevel = {parameter_number = 5, size = 1},
      maximumDimLevel = {parameter_number = 6, size = 1},
      invertSwitch = {parameter_number = 7, size = 1},
      autoOffTimer = {parameter_number = 8, size = 2},
      powerOnState = {parameter_number = 11, size = 1},
      ledIndicatorIntensity = {parameter_number = 14, size = 1},
      ledIntensityWhenOff = {parameter_number = 15, size = 1},
      ledIndicatorTimeout = {parameter_number = 17, size = 1},
      acPowerType = {parameter_number = 21, size = 1},
      switchType = {parameter_number = 22, size = 1}
    }
  },
  QUBINO_FLUSH_DIMMER = {
    MATCHING_MATRIX = {
      mfrs = 0x0159,
      product_types = 0x0001,
      product_ids = 0x0051
    },
    PARAMETERS = {
      input1SwitchType = {parameter_number = 1, size = 1},
      input2SwitchType = {parameter_number = 2, size = 1},
      enableAdditionalSwitch = {parameter_number = 20, size = 1},
      enableDoubleClick = {parameter_number = 21, size = 1},
      saveStateAfterPowerFail = {parameter_number = 30, size = 1},
      minimumDimmingValue = {parameter_number = 60, size = 1},
      dimmingTimeSoftOnOff = {parameter_number = 65, size = 2},
      dimmingTimeKeyPressed = {parameter_number = 66, size = 1},
      dimmingDuration = {parameter_number = 68, size = 1}
    }
  },
  QUBINO_DIN_DIMMER = {
    MATCHING_MATRIX = {
      mfrs = 0x0159,
      product_types = 0x0001,
      product_ids = 0x0052
    },
    PARAMETERS = {
      input1SwitchType = {parameter_number = 1, size = 1},
      enableDoubleClick = {parameter_number = 21, size = 1},
      saveStateAfterPowerFail = {parameter_number = 30, size = 1},
      minimumDimmingValue = {parameter_number = 60, size = 1},
      dimmingTimeSoftOnOff = {parameter_number = 65, size = 2},
      dimmingTimeKeyPressed = {parameter_number = 66, size = 1},
      dimmingDuration = {parameter_number = 68, size = 1}
    }
  },
  QUBINO_FLUSH_DIMMER_0_10V = {
    MATCHING_MATRIX = {
      mfrs = 0x0159,
      product_types = 0x0001,
      product_ids = 0x0053
    },
    PARAMETERS = {
      input1SwitchType = {parameter_number = 1, size = 1},
      enableDoubleClick = {parameter_number = 21, size = 1},
      saveStateAfterPowerFail = {parameter_number = 30, size = 1},
      minimumDimmingValue = {parameter_number = 60, size = 1},
      dimmingTimeSoftOnOff = {parameter_number = 65, size = 2},
      dimmingTimeKeyPressed = {parameter_number = 66, size = 1},
      dimmingDuration = {parameter_number = 68, size = 1}
    }
  },
  QUBINO_MINI_DIMMER = {
    MATCHING_MATRIX = {
      mfrs = 0x0159,
      product_types = 0x0001,
      product_ids = 0x0055
    },
    PARAMETERS = {
      input1SwitchType = {parameter_number = 1, size = 1},
      enableDoubleClick = {parameter_number = 21, size = 1},
      saveStateAfterPowerFail = {parameter_number = 30, size = 1},
      minimumDimmingValue = {parameter_number = 60, size = 1},
      dimmingTimeSoftOnOff = {parameter_number = 65, size = 2},
      dimmingTimeKeyPressed = {parameter_number = 66, size = 1},
      dimmingDuration = {parameter_number = 68, size = 1},
      calibrationTrigger = {parameter_number = 71, size = 1}
    }
  },
  QUBINO_FLUSH_1_2_RELAY = {
    MATCHING_MATRIX = {
      mfrs = 0x0159,
      product_types = 0x0002,
      product_ids = { 0x0051, 0x0052 }
    },
    PARAMETERS = {
      input1SwitchType = {parameter_number = 1, size = 1},
      input2SwitchType = {parameter_number = 2, size = 1},
      saveStateAfterPowerFail = {parameter_number = 30, size = 1},
      outputQ1SwitchSelection = {parameter_number = 63, size = 1},
      outputQ2SwitchSelection = {parameter_number = 64, size = 1}
    }
  },
  QUBINO_FLUSH_1D_RELAY = {
    MATCHING_MATRIX = {
      mfrs = 0x0159,
      product_types = 0x0002,
      product_ids = 0x0053
    },
    PARAMETERS = {
      input1SwitchType = {parameter_number = 1, size = 1},
      saveStateAfterPowerFail = {parameter_number = 30, size = 1},
      outputQ1SwitchSelection = {parameter_number = 63, size = 1}
    }
  },
  FIBARO_WALLI_DIMMER = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x1C01,
      product_ids = 0x1000
    },
    PARAMETERS = {
      ledFrameColourWhenOn = {parameter_number = 11, size = 1},
      ledFrameColourWhenOff = {parameter_number = 12, size = 1},
      ledFrameBrightness = {parameter_number = 13, size = 1},
      dimmStepSizeManControl = {parameter_number = 156, size = 1},
      timeToPerformDimmingStep = {parameter_number = 157, size = 2},
      doubleClickSetLevel = {parameter_number = 165, size = 1},
      buttonsOrientation = {parameter_number = 24, size = 1}
    }
  },
  FIBARO_WALLI_DOUBLE_SWITCH = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x1B01,
      product_ids = 0x1000
    },
    PARAMETERS = {
      ledFrameColourWhenOn = {parameter_number = 11, size = 1},
      ledFrameColourWhenOff = {parameter_number = 12, size = 1},
      ledFrameBrightness = {parameter_number = 13, size = 1},
      buttonsOperation = {parameter_number = 20, size = 1},
      buttonsOrientation = {parameter_number = 24, size = 1},
      outputsOrientation = {parameter_number = 25, size = 1}
    }
  },
  FIBARO_DOUBLE = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0203,
      product_ids = {0x1000, 0x2000, 0x3000}
    },
    PARAMETERS = {
      restoreState = {parameter_number = 9, size = 1},
      ch1OperatingMode = {parameter_number = 10, size = 1},
      ch1ReactionToSwitch = {parameter_number = 11, size = 1},
      ch1TimeParameter = {parameter_number = 12, size = 2},
      ch1PulseTime = {parameter_number = 13, size = 2},
      ch2OperatingMode = {parameter_number = 15, size = 1},
      ch2ReactionToSwitch = {parameter_number = 16, size = 1},
      ch2TimeParameter = {parameter_number = 17, size = 2},
      ch2PulseTime = {parameter_number = 18, size = 1},
      switchType = {parameter_number = 20, size = 1},
      flashingReports = {parameter_number = 21, size = 1},
      s1ScenesSent = {parameter_number = 28, size = 1},
      s2ScenesSent = {parameter_number = 29, size = 1},
      ch1EnergyReports = {parameter_number = 53, size = 2},
      ch2EnergyReports = {parameter_number = 57, size = 2},
      periodicPowerReports = {parameter_number = 58, size = 2},
      periodicEnergyReports = {parameter_number = 59, size = 2}
    }
  },
  FIBARO_WALL_PLUG_US = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x1401,
      product_ids = {0x1001,0x2000}
    },
    PARAMETERS = {
      restoreState = {parameter_number = 2, size = 1},
      overloadSafety = {parameter_number = 3, size = 2},
      standardPowerReports = {parameter_number = 11, size = 1},
      energyReportingThreshold = {parameter_number = 12, size = 2},
      periodicPowerReporting = {parameter_number = 13, size = 2},
      periodicReports = {parameter_number = 14, size = 2},
      ringColorOn = {parameter_number = 41, size = 1},
      ringColorOff = {parameter_number = 42, size = 1}
    }
  },
  FIBARO_WALL_PLUG_EU = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0602,
    },
    PARAMETERS = {
      alwaysActive = {parameter_number = 1, size = 1},
      restoreState = {parameter_number = 2, size = 1},
      overloadSafety = {parameter_number = 3, size = 2},
      standardPowerReports = {parameter_number = 11, size = 1},
      powerReportFrequency = {parameter_number = 12, size = 2},
      periodicReports = {parameter_number = 14, size = 2},
      ringColorOn = {parameter_number = 41, size = 1},
      ringColorOff = {parameter_number = 42, size = 1}
    }
  },
  FIBARO_SINGLE = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0403,
      product_ids = {0x1000, 0x2000, 0x3000}
    },
    PARAMETERS = {
      restoreState = {parameter_number = 9, size = 1},
      ch1OperatingMode = {parameter_number = 10, size = 1},
      ch1ReactionToSwitch = {parameter_number = 11, size = 1},
      ch1TimeParameter = {parameter_number = 12, size = 2},
      ch1PulseTime = {parameter_number = 13, size = 2},
      switchType = {parameter_number = 20, size = 1},
      flashingReports = {parameter_number = 21, size = 1},
      s1ScenesSent = {parameter_number = 28, size = 1},
      s2ScenesSent = {parameter_number = 29, size = 1},
      ch1EnergyReports = {parameter_number = 53, size = 2},
      periodicPowerReports = {parameter_number = 58, size = 2},
      periodicEnergyReports = {parameter_number = 59, size = 2}
    }
  },
  AEOTEC_NANO_DIMMER = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0003, 0x0103, 0x0203},
      product_ids = 0x006F
    },
    PARAMETERS = {
      minimumDimmingValue = {parameter_number = 131, size = 1}
    }
  },
  FIBARO_DIMMER_2 = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0102,
      product_ids = {0x1000, 0x2000, 0x3000}
    },
    PARAMETERS = {
      autoStepTime = {parameter_number = 6, size = 2},
      manualStepTime = {parameter_number = 8, size = 2},
      autoOff = {parameter_number = 10, size = 2},
      autoCalibration = {parameter_number = 13, size = 1},
      switchType = {parameter_number = 20, size = 1},
      threeWaySwitch = {parameter_number = 26, size = 1},
      loadControllMode = {parameter_number = 30, size = 1},
      levelCorrection = {parameter_number = 38, size = 2}
    }
  },
  ZOOZ_ZEN_30 = {
    MATCHING_MATRIX = {
      mfrs = 0x027A,
      product_types = 0xA000,
      product_ids = 0xA008
    },
    PARAMETERS = {
      powerFailure = {parameter_number = 12, size = 1},
      ledSceneControl = {parameter_number = 7, size = 1},
      relayLedMode = {parameter_number = 2, size = 1},
      relayLedColor = {parameter_number = 4, size = 1},
      relayLedBrightness = {parameter_number = 6, size = 1},
      relayAutoOff = {parameter_number = 10, size = 4},
      relayAutoOn = {parameter_number = 11, size = 4},
      relayLoadControl = {parameter_number = 20, size = 1},
      relayPhysicalDisabledBeh = {parameter_number = 25, size = 1},
      dimmerLedMode = {parameter_number = 1, size = 1},
      dimmerLedColor = {parameter_number = 3, size = 1},
      dimmerLedBright = {parameter_number = 5, size = 1},
      dimmerAutoOff = {parameter_number = 8, size = 4},
      dimmerAutoOn = {parameter_number = 9, size = 4},
      dimmerRampRate = {parameter_number = 13, size = 1},
      dimmerPaddleRamp = {parameter_number = 21, size = 1},
      dimmerMinimumBright = {parameter_number = 14, size = 1},
      dimmerMaximumBright = {parameter_number = 15, size = 1},
      dimmerCustomBright = {parameter_number = 23, size = 1},
      dimmerBrightControl = {parameter_number = 18, size = 1},
      dimmerDoubleTapFunc = {parameter_number = 17, size = 1},
      dimmerLoadControl = {parameter_number = 19, size = 1},
      dimmerPhysDisBeh = {parameter_number = 24, size = 1},
      dimmerNightBright = {parameter_number = 26, size = 1},
      dimmerPaddleControl = {parameter_number = 27, size = 1}
    }
  },
  LEVITON_DIMMER = {
    MATCHING_MATRIX = {
      mfrs = 0x001D,
      product_types = {0x3201, 0x3301},
      product_ids = 0x0001
    },
    PARAMETERS = {
      fadeOnTime = {parameter_number = 1, size = 1},
      fadeOffTime = {parameter_number = 2, size = 1},
      minimumLightLevel = {parameter_number = 3, size = 1},
      maximumLightLevel = {parameter_number = 4, size = 1},
      presetLightLevel = {parameter_number = 5, size = 1},
      levelIndicatorTimeout = {parameter_number = 6, size = 1},
      locatorLedStatus = {parameter_number = 7, size = 1},
      loadType = {parameter_number = 8, size = 1}
    }
  },
  SWITCH_LEVEL_INDICATOR = {
    MATCHING_MATRIX = {
      mfrs = 0x0063,
      product_types = {0x4457, 0x4944, 0x5044}
    },
    PARAMETERS = {
      ledIndicator = {parameter_number = 3, size = 1}
    }
  },
  SWITCH_BINARY_INDICATOR = {
    MATCHING_MATRIX = {
      mfrs = {0x0063, 0113},
      product_types = {0x4952, 0x5257, 0x5052, 5257}
    },
    PARAMETERS = {
      ledIndicator = {parameter_number = 3, size = 1}
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
