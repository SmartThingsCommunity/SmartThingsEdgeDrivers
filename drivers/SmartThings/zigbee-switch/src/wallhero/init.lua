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

local capabilities = require "st.capabilities"
local log = require "log"
local stDevice = require "st.device"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local Scenes = zcl_clusters.Scenes
local PRIVATE_CLUSTER_ID = 0x0006
local PRIVATE_ATTRIBUTE_ID = 0x6000
local MFG_CODE = 0x1235

local FINGERPRINTS = {
  { mfr = "WALL HERO", model = "ACL-401S4I", switches = 4, buttons = 0 },
  { mfr = "WALL HERO", model = "ACL-401S8I", switches = 4, buttons = 4 },
  { mfr = "WALL HERO", model = "ACL-401S3I", switches = 3, buttons = 0 },
  { mfr = "WALL HERO", model = "ACL-401S2I", switches = 2, buttons = 0 },
  { mfr = "WALL HERO", model = "ACL-401S1I", switches = 1, buttons = 0 },
  { mfr = "WALL HERO", model = "ACL-401ON", switches = 1, buttons = 0 }
}

local function can_handle_wallhero_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("wallhero")
      return true, subdriver
    end
  end
  return false
end

local function get_children_info(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.switches, fingerprint.buttons
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function create_child_devices(driver, device)
  local switch_amount, button_amount = get_children_info(device)
  local base_name = device.label:sub(1, device.label:find(" "))
  -- Create Switch 2-4
  for i = 2, switch_amount, 1 do
    if find_child(device, i) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        parent_assigned_child_key = string.format("%02X", i),
        label = base_name .. i,
        profile = "basic-switch",
        parent_device_id = device.id,
        vendor_provided_label = base_name .. i,
      }
      driver:try_create_device(metadata)
    end
  end
  -- Create Button if necessary
  for i = switch_amount+1, switch_amount+button_amount, 1 do
    if find_child(device, i) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        parent_assigned_child_key = string.format("%02X", i),
        label = base_name .. i,
        profile = "button",
        parent_device_id = device.id,
        vendor_provided_label = base_name .. i,
      }
      driver:try_create_device(metadata)
    end
  end
  device:refresh()
end

local function device_added(driver, device)
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then
    create_child_devices(driver, device)
  end
  -- Set Button Capabilities for scene switches
  if device:supports_capability_by_id(capabilities.button.ID) then
    device:emit_event(capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    device:emit_event(capabilities.button.supportedButtonValues({ "pushed" }, {visibility = {displayed = false } }))
  end
end

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  local value_map = { [true] = 0x00,[false] = 0x01 }
  if preferences ~= nil then
    local id = "stse.turnOffIndicatorLight"
    local old_value = old_preferences[id]
    local value = preferences[id]
    if value ~= nil and value ~= old_value  then
      value = value_map[value]
      local message = cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, value)
      device:send(message)
    end
  end
end

local function device_init(driver, device, event)
  device:set_find_child(find_child)
end

local function scenes_cluster_handler(driver, device, zb_rx)
  log.info("Enter scenes_cluster_handler")
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.button.button.pushed({ state_change = true }))
end

local wallheroswitch = {
  NAME = "Zigbee Wall Hero Switch",
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    infoChanged = device_info_changed
  },
  zigbee_handlers = {
    cluster = {
      [Scenes.ID] = {
        [Scenes.server.commands.RecallScene.ID] = scenes_cluster_handler,
      }
    }
  },
  can_handle = can_handle_wallhero_switch
}

return wallheroswitch
