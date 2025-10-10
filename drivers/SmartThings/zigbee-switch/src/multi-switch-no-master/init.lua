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
local st_device = require "st.device"
local utils = require "st.utils"
local configurations = require "configurations"

local function get_children_amount(device)
  for _, fingerprint in ipairs(require("multi-switch-no-master.fingerprints")) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    local children_amount = get_children_amount(device)
    if not (device.child_ids and utils.table_size(device.child_ids) ~= 0) then
      for i = 2, children_amount+1, 1 do
        local device_name_without_number = string.sub(device.label, 0,-2)
        local name = string.format("%s%d", device_name_without_number, i)
        if find_child(device, i) == nil then
          local metadata = {
            type = "EDGE_CHILD",
            label = name,
            profile = "basic-switch",
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%02X", i),
            vendor_provided_label = name,
          }
          driver:try_create_device(metadata)
        end
      end
    end
  end
  device:refresh()
end

local function device_init(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local multi_switch_no_master = {
  NAME = "multi switch no master",
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    added = device_added
  },
  can_handle = require("multi-switch-no-master.can_handle"),
}

return multi_switch_no_master
