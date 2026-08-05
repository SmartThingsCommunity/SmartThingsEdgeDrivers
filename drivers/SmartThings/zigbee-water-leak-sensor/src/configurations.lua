-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement

local devices = {
  CENTRALITE_WATER_LEAK_SENSOR = {
    FINGERPRINTS = {
      { mfr = "CentraLite", model = "3315-S" },
      { mfr = "CentraLite", model = "3315" },
      { mfr = "CentraLite", model = "3315-Seu" },
      { mfr = "CentraLite", model = "3315-L" },
      { mfr = "CentraLite", model = "3315-G" },
    },
    CONFIGURATION = {
      {
        use_battery_linear_voltage_handling = true,
        minV = 2.1,
        maxV = 3.0
      }
    }
  },

  SMARTTHINGS_WATER_LEAK_SENSOR = {
    FINGERPRINTS = {
      { mfr = "SmartThings", model = "moisturev4" }
    },
    CONFIGURATION = {
      {
        use_battery_voltage_table = true,
        battery_voltage_table = {
          [2.8] = 100,
          [2.7] = 100,
          [2.6] = 100,
          [2.5] = 90,
          [2.4] = 90,
          [2.3] = 70,
          [2.2] = 70,
          [2.1] = 50,
          [2.0] = 50,
          [1.9] = 30,
          [1.8] = 30,
          [1.7] = 15,
          [1.6] = 1,
          [1.5] = 0
        }
      }
    }
  },
  SAMJIN_WATER_LEAK_SENSOR = {
    FINGERPRINTS = {
      { mfr = "Samjin", model = "water" }
    },
    CONFIGURATION = {
      {
        cluster = PowerConfiguration.ID,
        attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
        minimum_interval = 30,
        maximum_interval = 21600,
        data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
        reportable_change = 16
      }
    }
  },
  SERCOMM_WATER_LEAK_SENSOR = {
    FINGERPRINTS = {
      { mfr = "Sercomm Corp.", model = "SZ-WTD03" }
    },
    CONFIGURATION = {
      {
        use_battery_linear_voltage_handling = true,
        minV = 2.1,
        maxV = 3.0
      }
    }
  },
  FRIENT_WATER_LEAK_SENSOR = {
    FINGERPRINTS = {
      { mfr = "frient A/S", model = "FLSZB-110" },
    },
    CONFIGURATION = {
      {
        use_battery_linear_voltage_handling = true,
        minV = 2.3,
        maxV = 3.0
      }
    }
  },
  NORTEK_WATER_LEAK_SENSOR = {
    FINGERPRINTS = {
      { mfr = "Nortek Security and Control", model = "F-ADT-WTR-1" }
    },
    CONFIGURATION = {
      {
        use_battery_linear_voltage_handling = true,
        minV = 2.1,
        maxV = 3.0
      },
      {
        cluster = TemperatureMeasurement.ID,
        attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
        minimum_interval = 30,
        maximum_interval = 300,
        data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
        reportable_change = 100
      }
    }
  }
}

local configurations = {}

configurations.get_device_configuration = function(zigbee_device)
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.FINGERPRINTS) do
      if zigbee_device:get_manufacturer() == fingerprint.mfr and zigbee_device:get_model() == fingerprint.model then
        return device.CONFIGURATION
      end
    end
  end
  return nil
end

return configurations
