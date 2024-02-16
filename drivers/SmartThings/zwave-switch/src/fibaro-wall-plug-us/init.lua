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

local FIBARO_WALL_PLUG_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x1401, model = 0x1001}, -- Fibaro Outlet
  {mfr = 0x010F, prod = 0x1401, model = 0x2000}, -- Fibaro Outlet
}

local function can_handle_fibaro_wall_plug(opts, driver, device, ...)
  for _, fingerprint in ipairs(FIBARO_WALL_PLUG_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-wall-plug-us")
      return true, subdriver
    end
  end
  return false
end

local function component_to_endpoint(device, component_id)
  if component_id == "main" then
    return {1}
  else
    return {2}
  end
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("smartplug%d", ep - 1)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local function device_init(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local fibaro_wall_plug = {
  NAME = "fibaro wall plug us",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = can_handle_fibaro_wall_plug,
}

return fibaro_wall_plug
