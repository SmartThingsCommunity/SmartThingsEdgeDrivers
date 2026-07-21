-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local IASZone = zcl_clusters.IASZone

local CONFIGURATIONS = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 1,
    maximum_interval = 1200, -- Zigbee poll interval is 600s. Added because the default reporting maximum_interval (180s) must be greater than 600s.
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  }
}

local function device_init(driver, device)
  if CONFIGURATIONS ~= nil then
    for _, attribute in ipairs(CONFIGURATIONS) do
      device:add_configured_attribute(attribute)
    end
  end
end

local shinasystem_smoke_sensor = {
  NAME = "shinasystem smoke sensor",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = require("shinasystem.can_handle"),
}
return shinasystem_smoke_sensor
