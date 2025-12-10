-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = zcl_clusters.PowerConfiguration

local capabilities = require "st.capabilities"

local utils = require "st.utils"

-- TODO: the IAS Zone changes should be replaced after supporting functions are included in the lua libs
local do_init = function(driver, device)
  device:remove_monitored_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
  device:remove_configured_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
end

local function samjin_battery_percentage_handler(driver, device, raw_value, zb_rx)
  local raw_percentage = raw_value.value - (200 - raw_value.value) / 2
  local percentage = utils.clamp_value(utils.round(raw_percentage / 2), 0, 100)
  device:emit_event(capabilities.battery.battery(percentage))
end

local samjin_driver = {
  NAME = "Samjin Sensor",
  lifecycle_handlers = {
    init = do_init
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = samjin_battery_percentage_handler
      }
    }
  },
  can_handle = require("samjin.can_handle"),
}

return samjin_driver
