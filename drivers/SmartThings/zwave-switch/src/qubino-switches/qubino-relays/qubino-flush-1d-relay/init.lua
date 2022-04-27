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

local MultichannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({ version = 3 })

local QUBINO_FLUSH_1D_RELAY_FINGERPRINT = {mfr = 0x0159, prod = 0x0002, model = 0x0053}

local function can_handle_qubino_flush_1d_relay(opts, driver, device, ...)
  return device:id_match(QUBINO_FLUSH_1D_RELAY_FINGERPRINT.mfr, QUBINO_FLUSH_1D_RELAY_FINGERPRINT.prod, QUBINO_FLUSH_1D_RELAY_FINGERPRINT.model)
end

local function do_configure(self, device)
  device:send(MultichannelAssociation:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}}))
  device:refresh()
end

local qubino_flush_1d_relay = {
  NAME = "qubino flush 1d relay",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_qubino_flush_1d_relay
}

return qubino_flush_1d_relay
