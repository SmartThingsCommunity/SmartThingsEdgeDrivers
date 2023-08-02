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
local constants = require "qubino-switches/constants/qubino-constants"

local function can_handle_qubino_flush_relay(opts, driver, device, cmd, ...)
  print("Driver: qubino parent can handle called")
  if( device:id_match(constants.QUBINO_MFR) ) then
    local subdriver = require("qubino-switches")
    return true, subdriver
  end
  return false
end

local qubino_relays = {
  NAME = "Qubino Relays",
  can_handle = can_handle_qubino_flush_relay,
  sub_drivers = {
    require("qubino-switches/qubino-relays"),
    require("qubino-switches/qubino-dimmer")
  }
}

return qubino_relays
