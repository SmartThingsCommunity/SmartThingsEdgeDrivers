-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.BarrierOperator

local driver_template = {
  supported_capabilities = {
    capabilities.doorControl,
    capabilities.contactSensor,
  },
  sub_drivers = require("sub_drivers"),
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local garage_door_opener = ZwaveDriver("zwave_garage_door_opener", driver_template)
garage_door_opener:run()
