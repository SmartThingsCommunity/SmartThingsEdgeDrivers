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

local QUBINO_DIMMER_FINGERPRINTS = {
  {mfr = 0x0159, prod = 0x0001, model = 0x0051}, -- Qubino Flush Dimmer
  {mfr = 0x0159, prod = 0x0001, model = 0x0052}, -- Qubino DIN Dimmer
  {mfr = 0x0159, prod = 0x0001, model = 0x0053}, -- Qubino Flush Dimmer 0-10V
  {mfr = 0x0159, prod = 0x0001, model = 0x0055}  -- Qubino Mini Dimmer
}

local function can_handle_qubino_dimmer(opts, driver, device, ...)
  for _, fingerprint in ipairs(QUBINO_DIMMER_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function do_configure(self, device)
  device:send(MultichannelAssociation:Remove({grouping_identifier = 1, node_ids = {}}))
  device:send(MultichannelAssociation:Set({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))
end

local qubino_dimmer = {
  NAME = "qubino dimmer",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_qubino_dimmer,
  sub_drivers = {
    require("qubino-switches/qubino-dimmer/qubino-din-dimmer")
  }
}

return qubino_dimmer
