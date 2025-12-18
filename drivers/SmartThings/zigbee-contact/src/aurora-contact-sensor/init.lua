-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local IASZone = clusters.IASZone


local AURORA_CONTACT_CONFIGURATION = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 30,
    maximum_interval = 300,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  }
}


local function device_init(driver, device)
  battery_defaults.use_battery_voltage_handling(device)

  for _, attribute in ipairs(AURORA_CONTACT_CONFIGURATION) do
    device:add_configured_attribute(attribute)
  end
end

local aurora_contact = {
  NAME = "Zigbee Aurora Contact Sensor",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = require("aurora-contact-sensor.can_handle"),
}

return aurora_contact
