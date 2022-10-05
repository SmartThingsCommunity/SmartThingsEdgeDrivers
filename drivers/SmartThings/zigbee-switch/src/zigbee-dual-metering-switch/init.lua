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

local ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT = {
  {mfr = "Aurora", model = "DoubleSocket50AU"}
}

local function can_handle_zigbee_dual_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function endpoint_to_component(device, endpoint)
  if endpoint == 2 then
    return "switch1"
  else
    return "main"
  end
end

local function component_to_endpoint(device, component)
  if component == "switch1" then
    return 2
  else
    return 1
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local zigbee_dual_metering_switch = {
  NAME = "zigbee dual metering switch",
  lifecycle_handlers = {
    init = map_components
  },
  can_handle = can_handle_zigbee_dual_metering_switch
}

return zigbee_dual_metering_switch
