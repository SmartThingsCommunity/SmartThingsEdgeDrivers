-- Copyright 2023 SmartThings
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
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local switch_defaults = require "st.zigbee.defaults.switch_defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff

local SHINASYSTEM_FINGERPRINTS = {
  { mfr = "ShinaSystem", model = "SBM300Z1", children = 0 },
  { mfr = "ShinaSystem", model = "SBM300Z2", children = 1 },
  { mfr = "ShinaSystem", model = "SBM300Z3", children = 2 },
  { mfr = "ShinaSystem", model = "SBM300Z4", children = 3 },
  { mfr = "ShinaSystem", model = "SBM300Z5", children = 4 },
  { mfr = "ShinaSystem", model = "SBM300Z6", children = 5 },
  { mfr = "ShinaSystem", model = "ISM300Z3", children = 2 }
}

local function is_handle_shinasystem_switch(opts, driver, device)
  for _, fingerprint in ipairs(SHINASYSTEM_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function get_children_amount(device)
  for _, fingerprint in ipairs(SHINASYSTEM_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local do_refresh_all = function(self, device)
  local children_amount = get_children_amount(device)
  for i = 1, children_amount+1, 1 do
    device:send(OnOff.attributes.OnOff:read(device):to_endpoint(i))
  end
end

local do_refresh = function(self, device)
  device:send(OnOff.attributes.OnOff:read(device):to_endpoint(tonumber(device.parent_assigned_child_key or 1)))
end

local do_switch_on = function(self, device)
  device:send(OnOff.server.commands.On(device):to_endpoint(tonumber(device.parent_assigned_child_key or 1)))
end

local do_switch_off = function(self, device)
  device:send(OnOff.server.commands.Off(device):to_endpoint(tonumber(device.parent_assigned_child_key or 1)))
end

local function do_configuration(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_CHILD then return end
  local attrCfg = device_management.attr_config(device, switch_defaults.default_on_off_configuration)
  local attrRead = zcl_clusters.OnOff.attributes.OnOff:read(device)
  local children_amount = get_children_amount(device)

  for ep_id = 1, children_amount+1 , 1 do
    device:send(device_management.build_bind_request(device, zcl_clusters.OnOff.ID, device.driver.environment_info.hub_zigbee_eui, ep_id))
    device:send(attrCfg:to_endpoint(ep_id))
    device:send(attrRead:to_endpoint(ep_id))
  end
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
    do_refresh_all(driver, device)
  end
end

local function device_init(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local handle_shinasystem_switch = {
  NAME = "Zigbee SiHAS Switch",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configuration,
    added = device_added
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = do_switch_on,
      [capabilities.switch.commands.off.NAME] = do_switch_off
    }
  },
  can_handle = is_handle_shinasystem_switch
}

return handle_shinasystem_switch