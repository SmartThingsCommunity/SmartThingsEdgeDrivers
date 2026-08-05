-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local MultichannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({ version = 3 })

local function do_configure(self, device)
  device:send(MultichannelAssociation:Remove({grouping_identifier = 1, node_ids = {}}))
  device:send(MultichannelAssociation:Set({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))
  device:send(Configuration:Set({parameter_number=42, size=2, configuration_value=1920}))
end

local qubino_din_dimmer = {
  NAME = "qubino DIN dimmer",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("qubino-switches.qubino-dimmer.qubino-din-dimmer.can_handle")
}

return qubino_din_dimmer
