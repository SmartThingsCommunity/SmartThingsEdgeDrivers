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


local MULTI_SWITCH_NO_MASTER_FINGERPRINTS = {
  { mfr = "DAWON_DNS", model = "PM-S240-ZB" },
  { mfr = "DAWON_DNS", model = "PM-S240R-ZB" },
  { mfr = "DAWON_DNS", model = "PM-S340-ZB" },
  { mfr = "DAWON_DNS", model = "PM-S340R-ZB" },
  { mfr = "DAWON_DNS", model = "PM-S250-ZB" },
  { mfr = "DAWON_DNS", model = "PM-S350-ZB" },
  { mfr = "DAWON_DNS", model = "ST-S250-ZB" },
  { mfr = "DAWON_DNS", model = "ST-S350-ZB" },
  { model = "E220-KR2N0Z0-HA" },
  { model = "E220-KR3N0Z0-HA" },
  { model = "E220-KR4N0Z0-HA" },
  { model = "E220-KR5N0Z0-HA" },
  { model = "E220-KR6N0Z0-HA" }
}

local function is_multi_switch_no_master(opts, driver, device)
  for _, fingerprint in ipairs(MULTI_SWITCH_NO_MASTER_FINGERPRINTS) do
      if device:get_manufacturer() == nil and device:get_model() == fingerprint.model then
        return true
      elseif device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
        return true
      end
  end

  return false
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("switch(%d)")
  return ep_num and tonumber(ep_num) + 1 or 1
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep - 1)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local multi_switch_no_master = {
  NAME = "multi switch no master",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = is_multi_switch_no_master
}

return multi_switch_no_master
