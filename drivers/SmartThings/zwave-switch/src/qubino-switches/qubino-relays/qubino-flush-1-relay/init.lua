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

--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({version=2})
--- @type st.zwave.CommandClass.MultiChannelAssociation
local MultiChannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({version=3})

local QUBINO_FLUSH_1_RELAY_FINGERPRINT = {mfr = 0x0159, prod = 0x0002, model = 0x0052}

local function can_handle_qubino_flush_1_relay(opts, driver, device, ...)
  return device:id_match(QUBINO_FLUSH_1_RELAY_FINGERPRINT.mfr, QUBINO_FLUSH_1_RELAY_FINGERPRINT.prod, QUBINO_FLUSH_1_RELAY_FINGERPRINT.model)
end

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
  can_handle = can_handle_qubino_flush_1_relay
}

return qubino_flush_1_relay
