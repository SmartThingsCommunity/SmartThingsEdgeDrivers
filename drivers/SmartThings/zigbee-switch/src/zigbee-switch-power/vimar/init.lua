-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local constants = require "st.zigbee.constants"
local device_management = require "st.zigbee.device_management"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local ElectricalMeasurement = zcl_clusters.ElectricalMeasurement

local function do_configure(driver, device)
  device:configure()
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1, {persist = true})
  device:send(device_management.build_bind_request(device, ElectricalMeasurement.ID, driver.environment_info.hub_zigbee_eui))
  device:send(ElectricalMeasurement.attributes.ActivePower:configure_reporting(device, 1, 15, 1))
  device:refresh()
end

local vimar_switch_power = {
  NAME = "Vimar Smart Actuator with Power Metering",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zigbee-switch-power.vimar.can_handle"),
}

return vimar_switch_power
