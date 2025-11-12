-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local stDevice = require "st.device"
local configurations = require "configurations"

local function get_children_amount(device)
  local FINGERPRINTS = require "hanssem.fingerprints"
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function create_child_devices(driver, device)
  local children_amount = get_children_amount(device)
  for i = 2, children_amount+1, 1 do
    local name = string.sub(device.label, 1, 9)
    if find_child(device, i) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        parent_assigned_child_key = string.format("%02X", i),
        label = name ..' '..i,
        profile = "basic-switch-no-firmware-update",
        parent_device_id = device.id,
        vendor_provided_label = name ..' '..i,
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
end

local function device_init(driver, device, event)
  device:set_find_child(find_child)
end

local HanssemSwitch = {
  NAME = "Zigbee Hanssem Switch",
  lifecycle_handlers = {
    added = device_added,
    init = configurations.power_reconfig_wrapper(device_init)
  },
  can_handle = require("hanssem.can_handle"),
}

return HanssemSwitch
