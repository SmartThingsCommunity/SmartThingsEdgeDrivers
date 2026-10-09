-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"

local WindowCovering = clusters.WindowCovering

local function shade_level_report_legacy_handler(driver, device, value, zb_rx)
  -- not implemented
end

local aqara_window_treatment_version_handler = {
  NAME = "Aqara Window Treatment Version Handler",
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = shade_level_report_legacy_handler
      }
    }
  },
  can_handle = require("aqara.version.can_handle"),
}

return aqara_window_treatment_version_handler
