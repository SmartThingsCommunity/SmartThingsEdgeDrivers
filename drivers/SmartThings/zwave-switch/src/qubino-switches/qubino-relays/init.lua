-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

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
