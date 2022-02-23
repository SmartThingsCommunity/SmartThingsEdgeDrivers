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

local FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT = {mfr = 0x010F, prod = 0x1B01, model = 0x1000}

local function can_handle_fibaro_walli_double_switch(opts, driver, device, ...)
  return device:id_match(FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT.mfr, FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT.prod, FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT.model)
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
    return {2}
  else
    return {1}
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local fibaro_walli_double_switch = {
  NAME = "fibaro walli double switch",
  lifecycle_handlers = {
    init = map_components
  },
  can_handle = can_handle_fibaro_walli_double_switch,
}

return fibaro_walli_double_switch
