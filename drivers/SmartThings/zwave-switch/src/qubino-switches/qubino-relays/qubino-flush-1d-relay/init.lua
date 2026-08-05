-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local MultichannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({ version = 3 })

local function do_configure(self, device)
  device:send(MultichannelAssociation:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}}))
  device:refresh()
end

local qubino_flush_1d_relay = {
  NAME = "qubino flush 1d relay",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("qubino-switches.qubino-relays.qubino-flush-1d-relay.can_handle")
}

return qubino_flush_1d_relay
