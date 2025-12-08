-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local constants = require "st.zigbee.constants"
local configurations = require "configurations"



local do_configure = function(self, device)
  device:refresh()
  device:configure()
end

local device_init = function(self, device)
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10000, {persist = true})
end

local frient_power_meter_handler = {
  NAME = "frient power meter handler",
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    doConfigure = do_configure,
  },
  can_handle = require("frient.can_handle"),
}

return frient_power_meter_handler