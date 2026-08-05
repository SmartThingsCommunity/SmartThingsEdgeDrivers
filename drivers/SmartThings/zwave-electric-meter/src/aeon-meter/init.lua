-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })

local do_configure = function (self, device)
  device:send(Configuration:Set({parameter_number = 101, size = 4, configuration_value = 4}))   -- combined power in watts...
  device:send(Configuration:Set({parameter_number = 111, size = 4, configuration_value = 300})) -- ...every 5 min
  device:send(Configuration:Set({parameter_number = 102, size = 4, configuration_value = 8}))   -- combined energy in kWh...
  device:send(Configuration:Set({parameter_number = 112, size = 4, configuration_value = 300})) -- ...every 5 min
  device:send(Configuration:Set({parameter_number = 103, size = 4, configuration_value = 0}))   -- no third report
end

local aeon_meter = {
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "aeon meter",
  can_handle = require("aeon-meter.can_handle"),
}

return aeon_meter
