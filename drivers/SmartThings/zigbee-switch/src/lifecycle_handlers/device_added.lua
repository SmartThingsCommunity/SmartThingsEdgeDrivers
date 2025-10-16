-- Copyright 2025 SmartThings
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

local find_child = require "lifecycle_handlers.find_child"

local function is_mcd_device(device)
  local components = device.profile.components
  if type(components) == "table" then
    local component_count = 0
    for _, component in pairs(components) do
        component_count = component_count + 1
    end
    return component_count >= 2
  end
end

return function(driver, device, event)
  local clusters = require "st.zigbee.zcl.clusters"
  local device_lib = require "st.device"

  local main_endpoint = device:get_endpoint(clusters.OnOff.ID)
  if is_mcd_device(device) == false and device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    for _, ep in ipairs(device.zigbee_endpoints) do
      if ep.id ~= main_endpoint then
        if device:supports_server_cluster(clusters.OnOff.ID, ep.id) then
          device:set_find_child(find_child)
          if find_child(device, ep.id) == nil then
            local name = string.format("%s %d", device.label, ep.id)
            local child_profile = "basic-switch"
            driver:try_create_device(
              {
                type = "EDGE_CHILD",
                label = name,
                profile = child_profile,
                parent_device_id = device.id,
                parent_assigned_child_key = string.format("%02X", ep.id),
                vendor_provided_label = name
              }
            )
          end
        end
      end
    end
  end
end
