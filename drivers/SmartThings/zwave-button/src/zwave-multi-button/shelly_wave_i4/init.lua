-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
-- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })



local do_configure = function(self, device)
  device:refresh()
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 1, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 2, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 3, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 4, size = 1 }))
  device:send(Association:Set({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))
end

local shelly_wave_i4 = {
  NAME = "Shelly Wave i4",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zwave-multi-button.shelly_wave_i4.can_handle"),
}

return shelly_wave_i4
