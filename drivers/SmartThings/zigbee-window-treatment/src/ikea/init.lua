-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local PowerConfiguration = clusters.PowerConfiguration

-- IKEA devices report BatteryPercentageRemaining in 1% units (0-100)
-- rather than the 0.5% units (0-200) defined by the ZCL spec, so the
-- default handler would halve the reported percentage. Emit the raw
-- value instead, matching the IKEA handling in the zigbee-button and
-- zigbee-dimmer-remote drivers.
local function battery_perc_attr_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))
end

local ikea_window_treatment = {
  NAME = "ikea window treatment",
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      }
    }
  },
  can_handle = require("ikea.can_handle"),
}

return ikea_window_treatment
