-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local battery_report_handler = function(driver, device, value)
   device:emit_event(capabilities.battery.battery(value.value))
end

local raw_battery_percentage_driver = {
  NAME = "Yale Raw Battery Percentage",
  zigbee_handlers = {
    attr = {
      [clusters.PowerConfiguration.ID] = {
        [clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_report_handler
      }
    }
  },
  can_handle = require("yale.use-raw-battery-percentage.can_handle")
}

return raw_battery_percentage_driver
