local devices = {
  AEOTEC_HOME_ENERGY_METER_GEN8_1_PHASE = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types = {0x0003, 0x0102 },
      product_ids = 0x0033
    },
    PARAMETERS = {
      thresholdCheck = {parameter_number = 3, size = 1},
      imWThresholdTotal = {parameter_number = 4, size = 2},
      imWThresholdPhaseA = {parameter_number = 5, size = 2},
      exWThresholdTotal = {parameter_number = 8, size = 2},
      exWThresholdPhaseA = {parameter_number = 9, size = 2},
      imtWPctThresholdTotal = {parameter_number = 12, size = 1},
      imWPctThresholdPhaseA = {parameter_number = 13, size = 1},
      exWPctThresholdTotal = {parameter_number = 16, size = 1},
      exWPctThresholdPhaseA = {parameter_number = 17, size = 1},
      autoRootDeviceReport = {parameter_number = 32, size = 1},
    }
  },
  AEOTEC_HOME_ENERGY_METER_GEN8_2_PHASE = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types =  0x0103,
      product_ids = 0x002E
    },
    PARAMETERS = {
      thresholdCheck = {parameter_number = 3, size = 1},
      imWThresholdTotal = {parameter_number = 4, size = 2},
      imWThresholdPhaseA = {parameter_number = 5, size = 2},
      imWThresholdPhaseB = {parameter_number = 6, size = 2},
      exWThresholdTotal = {parameter_number = 8, size = 2},
      exWThresholdPhaseA = {parameter_number = 9, size = 2},
      exWThresholdPhaseB = {parameter_number = 10, size = 2},
      imtWPctThresholdTotal = {parameter_number = 12, size = 1},
      imWPctThresholdPhaseA = {parameter_number = 13, size = 1},
      imWPctThresholdPhaseB = {parameter_number = 14, size = 1},
      exWPctThresholdTotal = {parameter_number = 16, size = 1},
      exWPctThresholdPhaseA = {parameter_number = 17, size = 1},
      exWPctThresholdPhaseB = {parameter_number = 18, size = 1},
      autoRootDeviceReport = {parameter_number = 32, size = 1},
    }
  },
  AEOTEC_HOME_ENERGY_METER_GEN8_3_PHASE = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types = {0x0003, 0x0102},
      product_ids = 0x0034
    },
    PARAMETERS = {
      thresholdCheck = {parameter_number = 3, size = 1},
      imWThresholdTotal = {parameter_number = 4, size = 2},
      imWThresholdPhaseA = {parameter_number = 5, size = 2},
      imWThresholdPhaseB = {parameter_number = 6, size = 2},
      imWThresholdPhaseC = {parameter_number = 7, size = 2},
      exWThresholdTotal = {parameter_number = 8, size = 2},
      exWThresholdPhaseA = {parameter_number = 9, size = 2},
      exWThresholdPhaseB = {parameter_number = 10, size = 2},
      exWThresholdPhaseC = {parameter_number = 11, size = 2},
      imtWPctThresholdTotal = {parameter_number = 12, size = 1},
      imWPctThresholdPhaseA = {parameter_number = 13, size = 1},
      imWPctThresholdPhaseB = {parameter_number = 14, size = 1},
      imWPctThresholdPhaseC = {parameter_number = 15, size = 1},
      exWPctThresholdTotal = {parameter_number = 16, size = 1},
      exWPctThresholdPhaseA = {parameter_number = 17, size = 1},
      exWPctThresholdPhaseB = {parameter_number = 18, size = 1},
      exWPctThresholdPhaseC = {parameter_number = 19, size = 1},
      autoRootDeviceReport = {parameter_number = 32, size = 1},
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