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

local MULTI_SWITCH_NO_MASTER_FINGERPRINTS = {
  { mfr = "DAWON_DNS", model = "PM-S240-ZB", children = 1 },
  { mfr = "DAWON_DNS", model = "PM-S240R-ZB", children = 1 },
  { mfr = "DAWON_DNS", model = "PM-S250-ZB", children = 1 },
  { mfr = "DAWON_DNS", model = "PM-S340-ZB", children = 2 },
  { mfr = "DAWON_DNS", model = "PM-S340R-ZB", children = 2 },
  { mfr = "DAWON_DNS", model = "PM-S350-ZB", children = 2 },
  { mfr = "DAWON_DNS", model = "ST-S250-ZB", children = 1 },
  { mfr = "DAWON_DNS", model = "ST-S350-ZB", children = 2 },
  { mfr = "ORVIBO", model = "074b3ffba5a045b7afd94c47079dd553", children = 1 },
  { mfr = "ORVIBO", model = "9f76c9f31b4c4a499e3aca0977ac4494", children = 2 },
  { mfr = "REXENSE", model = "HY0002", children = 1 },
  { mfr = "REXENSE", model = "HY0003", children = 2 },
  { mfr = "REX", model = "HY0096", children = 1 },
  { mfr = "REX", model = "HY0097", children = 2 },
  { mfr = "HEIMAN", model = "HS2SW2L-EFR-3.0", children = 1 },
  { mfr = "HEIMAN", model = "HS2SW3L-EFR-3.0", children = 2 },
  { mfr = "HEIMAN", model = "HS6SW2A-W-EF-3.0", children = 1 },
  { mfr = "HEIMAN", model = "HS6SW3A-W-EF-3.0", children = 2 },
  { mfr = "eWeLink", model = "ZB-SW02", children = 1 },
  { mfr = "eWeLink", model = "ZB-SW03", children = 2 },
  { mfr = "eWeLink", model = "ZB-SW04", children = 3 },
  { mfr = "SMARTvill", model = "SLA02", children = 1 },
  { mfr = "SMARTvill", model = "SLA03", children = 2 },
  { mfr = "SMARTvill", model = "SLA04", children = 3 },
  { mfr = "SMARTvill", model = "SLA05", children = 4 },
  { mfr = "SMARTvill", model = "SLA06", children = 5 },
  { mfr = "ShinaSystem", model = "SBM300Z2", children = 1 },
  { mfr = "ShinaSystem", model = "SBM300Z3", children = 2 },
  { mfr = "ShinaSystem", model = "SBM300Z4", children = 3 },
  { mfr = "ShinaSystem", model = "SBM300Z5", children = 4 },
  { mfr = "ShinaSystem", model = "SBM300Z6", children = 5 },
  { model = "E220-KR2N0Z0-HA", children = 1 },
  { model = "E220-KR3N0Z0-HA", children = 2 },
  { model = "E220-KR4N0Z0-HA", children = 3 },
  { model = "E220-KR5N0Z0-HA", children = 4 },
  { model = "E220-KR6N0Z0-HA", children = 5 }
}

local function is_multi_switch_no_master(opts, driver, device)
  for _, fingerprint in ipairs(MULTI_SWITCH_NO_MASTER_FINGERPRINTS) do
    if device:get_model() == fingerprint.model and (device:get_manufacturer() == nil or device:get_manufacturer() == fingerprint.mfr) then
      local subdriver = require("multi-switch-no-master")
      return true, subdriver
    end
  end
  return false
end

local function get_children_amount(device)
  for _, fingerprint in ipairs(MULTI_SWITCH_NO_MASTER_FINGERPRINTS) do
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
    init = device_init,
    added = device_added
  },
  can_handle = is_multi_switch_no_master
}

return multi_switch_no_master

