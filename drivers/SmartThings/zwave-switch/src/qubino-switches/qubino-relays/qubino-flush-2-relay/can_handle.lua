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
local QUBINO_FLUSH_2_RELAY_FINGERPRINT = { mfr = 0x0159, prod = 0x0002, model = 0x0051 }

local function can_handle_qubino_flush_2_relay(opts, driver, device, ...)
  print("Driver: qubino_flush_2_relay can handle called")
  if device:id_match(QUBINO_FLUSH_2_RELAY_FINGERPRINT.mfr, QUBINO_FLUSH_2_RELAY_FINGERPRINT.prod, QUBINO_FLUSH_2_RELAY_FINGERPRINT.model) then
    local subdriver = require("qubino-switches/qubino-relays/qubino-flush-2-relay")
    return true, subdriver
  end
  return false
end

local qubino_flush_2_relay = {
  NAME = "qubino flush 2 relay",
  can_handle = can_handle_qubino_flush_2_relay
}

return qubino_flush_2_relay
