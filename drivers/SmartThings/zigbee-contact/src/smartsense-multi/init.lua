-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local multi_utils = require "multi-sensor/multi_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local contactSensor_defaults = require "st.zigbee.defaults.contactSensor_defaults"

local ACCELERATION_MASK = 0x01
local CONTACT_MASK = 0x02
local SMARTSENSE_MULTI_CLUSTER = 0xFC03
local SMARTSENSE_MULTI_ACC_CMD = 0x00
local SMARTSENSE_MULTI_XYZ_CMD = 0x05
local SMARTSENSE_MULTI_STATUS_CMD = 0x07
local SMARTSENSE_MULTI_STATUS_REPORT_CMD = 0x09
local SMARTSENSE_PROFILE_ID = 0xFC01


  },
  can_handle = require("smartsense-multi.can_handle"),
}

return smartsense_multi
