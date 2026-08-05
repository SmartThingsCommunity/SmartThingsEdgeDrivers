-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zigbee_constants = require "st.zigbee.constants"
local configurations = require "configurations"

local do_init = function(self, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000000, {persist = true})
  device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1000, {persist = true})
end

local ezex_switch_handler = {
  NAME = "ezex switch handler",
  lifecycle_handlers = {
    init = configurations.reconfig_wrapper(do_init)
  },
  can_handle = require("ezex.can_handle"),
}

return ezex_switch_handler
