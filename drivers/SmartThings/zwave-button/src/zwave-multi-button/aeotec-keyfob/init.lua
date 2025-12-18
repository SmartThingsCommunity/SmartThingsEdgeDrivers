-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version=1 })

local do_configure = function(self, device)
  device:refresh()
  device:send(Configuration:Set({ configuration_value = 1, parameter_number = 250, size = 1 }))
  device:send(Association:Set({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))
end

local aeotec_keyfob = {
  NAME = "Aeotec keyfob",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zwave-multi-button.aeotec-keyfob.can_handle"),
}

return aeotec_keyfob
