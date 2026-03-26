-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"


-- TODO: the IAS Zone changes should be replaced after supporting functions are included in the lua libs
local do_init = function(driver, device)
  battery_defaults.build_linear_voltage_init(2.4, 2.7)(driver, device)
  device:remove_monitored_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
  device:remove_configured_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
end


local iris_motion_handler = {
  NAME = "Iris Motion Handler",
  lifecycle_handlers = {
    init = do_init
  },
  can_handle = require("iris.can_handle"),
}

return iris_motion_handler
