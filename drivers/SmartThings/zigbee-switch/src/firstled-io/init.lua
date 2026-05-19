-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local Scenes = zcl_clusters.Scenes
local PRIVATE_CLUSTER_ID = 0xFCCA
local MFG_CODE = 0x1235
local FINGERPRINTS = require("firstled-io.fingerprints")

local preference_map = {
  ["backlight"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0000,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
  },
  ["powerOnStatus"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0001,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
  },
  ["stse.changeToWirelessSwitch"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0002,
    mfg_code = MFG_CODE,
    data_type = data_types.Boolean
  }
}

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preference_map) do
      local old_value = old_preferences[id]
      local value = preferences[id]
      if value ~= nil and value ~= old_value then
	    if attr.data_type == data_types.Uint8 then
	      value = tonumber(value)
		end
        device:send(cluster_base.write_manufacturer_specific_attribute(device, attr.cluster_id, attr.attribute_id,
          attr.mfg_code, attr.data_type, value))
      end
    end
  end
end

local function get_children_amount(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function get_button_amount(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.buttons
    end
  end
end

local function get_child_profile_name(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.child_profile
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_added(driver, device)
  -- Only create children for the actual Zigbee device and not the children
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    local children_amount = get_children_amount(device)
    if children_amount >= 2 then
      for i = 2, children_amount, 1 do
        if find_child(device, i) == nil then
          local name = string.format("%s%d", string.sub(device.label, 0, -2), i)
          local child_profile = get_child_profile_name(device)
          local metadata = {
            type = "EDGE_CHILD",
            label = name,
            profile = child_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%02X", i),
            vendor_provided_label = name
          }
          driver:try_create_device(metadata)
        end
      end
    end

  -- Create Button if necessary
    local button_amount = get_button_amount(device)
    if button_amount >= 1 then
      for i = children_amount+1,children_amount + button_amount, 1 do
        if find_child(device, i) == nil then
          local name = string.format("%s%d", string.sub(device.label, 0, -2), i)
          local metadata = {
            type = "EDGE_CHILD",
            label = name,
            profile = "button",
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%02X", i),
            vendor_provided_label = name,
          }
          driver:try_create_device(metadata)
        end
      end
    end

    -- for wireless button
    device:emit_event(capabilities.button.numberOfButtons({ value = children_amount },
      { visibility = { displayed = false } }))

  elseif device.network_type == "DEVICE_EDGE_CHILD" then
    device:emit_event(capabilities.button.numberOfButtons({ value = 1 },
      { visibility = { displayed = false } }))
  end
  device:emit_event(capabilities.button.supportedButtonValues({ "pushed" },
    { visibility = { displayed = false } }))
end

local function scenes_cluster_handler(driver, device, zb_rx)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.button.button.pushed({ state_change = true }))
end

local function device_init(self, device)
  -- for multiple switch
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local firstled_switch_handler = {
  NAME = "FIRSTLED Switch Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  infoChanged = device_info_changed
  },
  zigbee_handlers = {
    cluster = {
      [Scenes.ID] = {
        [Scenes.server.commands.RecallScene.ID] = scenes_cluster_handler,
      }
    }
  },
  can_handle = require("firstled-io.can_handle"),
}

return firstled_switch_handler
