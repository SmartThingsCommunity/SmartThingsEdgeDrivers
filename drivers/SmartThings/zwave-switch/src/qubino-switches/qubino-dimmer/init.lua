-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local MultichannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({ version = 3 })

local function do_configure(self, device)
  device:send(MultichannelAssociation:Remove({grouping_identifier = 1, node_ids = {}}))
  device:send(MultichannelAssociation:Set({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))
end

local qubino_dimmer = {
  NAME = "qubino dimmer",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("qubino-switches.qubino-dimmer.can_handle"),
  sub_drivers = require("qubino-switches.qubino-dimmer.sub_drivers"),
}

return qubino_dimmer
