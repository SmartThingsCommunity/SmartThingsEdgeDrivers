-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local battery_defaults = require "st.zigbee.defaults.battery_defaults"


local battery_voltage_motion = {
  NAME = "Battery Voltage Motion Sensor",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0)
  },
  can_handle = require("battery-voltage.can_handle"),
}

return battery_voltage_motion
