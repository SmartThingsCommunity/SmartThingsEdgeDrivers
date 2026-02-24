-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local data_types = require "st.zigbee.data_types"

local custom_clusters = {
  motor = {
    id = 0xFCC8,
    mfg_specific_code = 0x1235,
    attributes = {
      state_value = {
        id = 0x0000,
        value_type = data_types.Uint8,
      }
    }
  }
}

return custom_clusters
