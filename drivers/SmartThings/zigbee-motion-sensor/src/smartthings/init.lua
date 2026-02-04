-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local battery_table = {
  [2.80] = 100,
  [2.70] = 100,
  [2.60] = 100,
  [2.50] = 90,
  [2.40] = 90,
  [2.30] = 70,
  [2.20] = 70,
  [2.10] = 50,
  [2.00] = 50,
  [1.90] = 30,
  [1.80] = 30,
  [1.70] = 15,
  [1.60] = 1,
  [1.50] = 0
}

local function init_handler(driver, device)
  battery_defaults.enable_battery_voltage_table(device, battery_table)
  -- TODO: the IAS Zone changes should be replaced after supporting functions are included in the lua libs
  device:remove_monitored_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
  device:remove_configured_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
end

local smartthings_motion = {
  NAME = "SmartThings Motion Sensor",
  lifecycle_handlers = {
    init = init_handler
  },
  can_handle = require("smartthings.can_handle"),
}

return smartthings_motion
