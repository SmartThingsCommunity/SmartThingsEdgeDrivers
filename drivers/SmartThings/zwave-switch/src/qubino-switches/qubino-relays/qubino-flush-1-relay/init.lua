-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({version=2})
--- @type st.zwave.CommandClass.MultiChannelAssociation
local MultiChannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({version=3})

local function do_configure(self, device)
  -- Hub automatically adds device to multiChannelAssosciationGroup and this needs to be removed
  device:send(MultiChannelAssociation:Remove({grouping_identifier = 1, node_ids = {}}))
  device:send(Association:Set({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))

  local association_cmd = Association:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}})
  -- This command needs to be sent before creating component
  -- That's why MultiChannel is forced here
  association_cmd.dst_channels = {4}
  device:send(association_cmd)
end

local qubino_flush_1_relay = {
  NAME = "qubino flush 1 relay",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("qubino-switches.qubino-relays.qubino-flush-1-relay.can_handle")
}

return qubino_flush_1_relay
