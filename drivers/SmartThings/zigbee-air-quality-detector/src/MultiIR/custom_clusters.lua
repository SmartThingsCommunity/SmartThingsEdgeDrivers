-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local data_types = require "st.zigbee.data_types"

local custom_clusters = {
  carbonDioxide = {
    id = 0xFCC3,
    mfg_specific_code = 0x1235,
    attributes = {
      measured_value = {
        id = 0x0000,
        value_type = data_types.Uint16,
      }
    }
  },
  particulate_matter = {
    id = 0xFCC1,
    mfg_specific_code = 0x1235,
    attributes = {
      pm2_5_MeasuredValue = {
        id = 0x0000,
        value_type = data_types.Uint16,
      },
      pm1_0_MeasuredValue = {
        id = 0x0001,
        value_type = data_types.Uint16,
      },
      pm10_MeasuredValue = {
        id = 0x0002,
        value_type = data_types.Uint16,
      }
    }
  },
  unhealthy_gas = {
    id = 0xFCC2,
    mfg_specific_code = 0x1235,
    attributes = {
      CH2O_MeasuredValue = {
        id = 0x0000,
        value_type = data_types.SinglePrecisionFloat,
      },
      tvoc_MeasuredValue = {
        id = 0x0001,
        value_type = data_types.SinglePrecisionFloat,
      }
    }
  },
  AQI = {
    id = 0xFCC5,
    mfg_specific_code = 0x1235,
    attributes = {
      AQI_value = {
        id = 0x0000,
        value_type = data_types.Uint16,
      }
    }
  }
}

return custom_clusters
