-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })

local do_configure = function (self, device)
  device:send(Configuration:Set({parameter_number = 101, size = 4, configuration_value = 3}))   -- report total power in Watts and total energy in kWh...
  device:send(Configuration:Set({parameter_number = 102, size = 4, configuration_value = 0}))   -- disable group 2...
  device:send(Configuration:Set({parameter_number = 103, size = 4, configuration_value = 0}))   -- disable group 3...
  device:send(Configuration:Set({parameter_number = 111, size = 4, configuration_value = 300})) -- ...every 5 min
  device:send(Configuration:Set({parameter_number = 90, size = 1, configuration_value = 0}))    -- enabling automatic reports, disabled selective reporting...
  device:send(Configuration:Set({parameter_number = 13, size = 1, configuration_value = 0}))   -- disable CRC16 encapsulation
end

local aeotec_gen5_meter = {
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "aeotec gen5 meter",
  can_handle = require("aeotec-gen5-meter.can_handle"),
}

return aeotec_gen5_meter
