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

local QUBINO_FLUSH_RELAY_FINGERPRINT = {
  {mfr = 0x0159, prod = 0x0002, model = 0x0051}, -- Qubino Flush 2 Relay
  {mfr = 0x0159, prod = 0x0002, model = 0x0052}, -- Qubino Flush 1 Relay
  {mfr = 0x0159, prod = 0x0002, model = 0x0053}  -- Qubino Flush 1D Relay
}

local function can_handle_qubino_flush_relay(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(QUBINO_FLUSH_RELAY_FINGERPRINT) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

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
  can_handle = can_handle_qubino_flush_relay,
  sub_drivers = {
    require("qubino-switches/qubino-relays/qubino-flush-2-relay"),
    require("qubino-switches/qubino-relays/qubino-flush-1-relay"),
    require("qubino-switches/qubino-relays/qubino-flush-1d-relay")
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
}

return qubino_relays
