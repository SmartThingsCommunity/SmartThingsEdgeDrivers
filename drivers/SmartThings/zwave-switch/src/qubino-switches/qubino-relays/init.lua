-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local Association = (require "st.zwave.CommandClass.Association")({ version = 2 })

local function do_configure(self, device)
  local association_cmd = Association:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}})
  -- This command needs to be sent before creating component
  -- That's why MultiChannel is forced here
  association_cmd.dst_channels = {3}
  device:send(association_cmd)
  device:refresh()
end

local qubino_relays = {
  NAME = "Qubino Relays",
  can_handle = require("qubino-switches.qubino-relays.can_handle"),
  sub_drivers = require("qubino-switches.qubino-relays.sub_drivers"),
  lifecycle_handlers = {
    doConfigure = do_configure
  },
}

return qubino_relays
