-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })



local function do_configure(self, device)
  device:refresh()
  --configuration value : 1 (pressed), 2(double), 4(pushed_3x), 8(held & down_hold)
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 21, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 22, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 23, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 24, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 25, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 26, size = 1 }))
end

local fibaro_keyfob = {
  NAME = "Fibaro keyfob",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zwave-multi-button.fibaro-keyfob.can_handle"),
}

return fibaro_keyfob
