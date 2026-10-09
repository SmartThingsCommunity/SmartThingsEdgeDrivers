-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local data_types = require "st.zigbee.data_types"

local custom_clusters = {
  shus_smart_mattress = {
    id = 0xFCC2,
    mfg_specific_code = 0x1235,
    attributes = {
      left_ai_mode = {
        id = 0x0006,
        value_type = data_types.Boolean,
        value = {
          on = true,
          off = false,
        }
      },
      right_ai_mode = {
        id = 0x0007,
        value_type = data_types.Boolean,
        value = {
          on = true,
          off = false,
        }
      },
      auto_inflation = {
        id = 0x0009,
        value_type = data_types.Boolean,
        value = {
          on = true,
          off = false,
        }
      },
      strong_exp_mode = {
        id = 0x000A,
        value_type = data_types.Boolean,
        value = {
          on = true,
          off = false,
        }
      },
      left_back = {
        id = 0x0000,
        value_type = data_types.Uint8,
        value = {
          soft = 0,
          hard = 1,
        }
      },
      left_waist = {
        id = 0x0001,
        value_type = data_types.Uint8,
        value = {
          soft = 0,
          hard = 1,
        }
      },
      left_hip = {
        id = 0x0002,
        value_type = data_types.Uint8,
        value = {
          soft = 0,
          hard = 1,
        }
      },
      right_back = {
        id = 0x0003,
        value_type = data_types.Uint8,
        value = {
          soft = 0,
          hard = 1,
        }
      },
      right_waist = {
        id = 0x0004,
        value_type = data_types.Uint8,
        value = {
          soft = 0,
          hard = 1,
        }
      },
      right_hip = {
        id = 0x0005,
        value_type = data_types.Uint8,
        value = {
          soft = 0,
          hard = 1,
        }
      },
      yoga = {
        id = 0x0008,
        value_type = data_types.Uint8,
        value = {
          stop = 0,
          left = 1,
          right = 2,
          both = 3,
        }
      },
      left_back_level = {
        id = 0x000C,
        value_type = data_types.Uint8
      },
      left_waist_level = {
        id = 0x000D,
        value_type = data_types.Uint8
      },
      left_hip_level = {
        id = 0x000E,
        value_type = data_types.Uint8
      },
      right_back_level = {
        id = 0x000F,
        value_type = data_types.Uint8
      },
      right_waist_level = {
        id = 0x0010,
        value_type = data_types.Uint8
      },
      right_hip_level = {
        id = 0x0011,
        value_type = data_types.Uint8
      }
    }
  }
}

return custom_clusters
