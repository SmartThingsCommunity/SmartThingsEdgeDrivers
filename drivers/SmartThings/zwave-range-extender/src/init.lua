-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"

local driver_template = {
  zwave_handlers = {}
}
local zwave_range_extender_driver = ZwaveDriver("zwave-range-extender", driver_template)

zwave_range_extender_driver:run()
