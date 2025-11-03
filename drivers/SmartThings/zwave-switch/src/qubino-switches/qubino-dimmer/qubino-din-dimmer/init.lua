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
