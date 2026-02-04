-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement

local COMPACTA_TEMP_CONFIG = {
  minimum_interval = 30,
  maximum_interval = 300,
  reportable_change = 100,
  endpoint = 0x03
}

local function do_configure(driver, device)
  device:configure()
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
    device,
    COMPACTA_TEMP_CONFIG.minimum_interval,
    COMPACTA_TEMP_CONFIG.maximum_interval,
    COMPACTA_TEMP_CONFIG.reportable_change
  ):to_endpoint(COMPACTA_TEMP_CONFIG.endpoint))
end

local function added_handler(driver, device)
  device:refresh()
end

local compacta_driver = {
  NAME = "Compacta Sensor",
  lifecycle_handlers = {
    added = added_handler,
    doConfigure = do_configure
  },
  can_handle = require("compacta.can_handle"),
}

return compacta_driver
