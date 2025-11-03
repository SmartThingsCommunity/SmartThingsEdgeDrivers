-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local constants = require "st.zigbee.constants"

local function do_configure(driver, device)
  device:configure()

  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1, {persist = true})

  device:refresh()
end

local aurora_relay = {
  NAME = "Aurora Relay/SALUS",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zigbee-switch-power.aurora-relay.can_handle"),
}

return aurora_relay
