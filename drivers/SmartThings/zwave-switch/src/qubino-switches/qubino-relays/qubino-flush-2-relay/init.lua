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

local QUBINO_FLUSH_2_RELAY_FINGERPRINT = {mfr = 0x0159, prod = 0x0002, model = 0x0051}

local function can_handle_qubino_flush_2_relay(opts, driver, device, ...)
  return device:id_match(QUBINO_FLUSH_2_RELAY_FINGERPRINT.mfr, QUBINO_FLUSH_2_RELAY_FINGERPRINT.prod, QUBINO_FLUSH_2_RELAY_FINGERPRINT.model)
end

local function component_to_endpoint(device, component_id)
    if component_id == "main" then
      return { 1 }
    elseif component_id == "extraTemperatureSensor" then
      return { 3 }
    else
      local ep_num = math.floor(component_id:match("switch(%d)"))
      return { ep_num and tonumber(ep_num)}
    end
end

local function endpoint_to_component(device, ep)
    if ep == 2 then
      return string.format("switch%d", ep)
    elseif ep == 3 then
      return "extraTemperatureSensor"
    else
      return "main"
    end
end

local function map_components(self, device)
    device:set_endpoint_to_component_fn(endpoint_to_component)
    device:set_component_to_endpoint_fn(component_to_endpoint)
end

local qubino_flush_2_relay = {
  NAME = "qubino flush 2 relay",
  lifecycle_handlers = {
    init = map_components
  },
  can_handle = can_handle_qubino_flush_2_relay
}

return qubino_flush_2_relay
