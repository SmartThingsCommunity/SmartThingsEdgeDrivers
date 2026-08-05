-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local utils = require "st.utils"
local battery_config = utils.deep_copy(battery_defaults.default_percentage_configuration)
battery_config.reportable_change = 0x10
battery_config.data_type = zcl_clusters.PowerConfiguration.attributes.BatteryVoltage.base_type

local function init_handler(self, device)
  device:add_configured_attribute(battery_config)
end

local samjin_button = {
  NAME = "Samjin Button Handler",
  lifecycle_handlers = {
    init = init_handler
  },
  can_handle = require("samjin.can_handle"),
}

return samjin_button
