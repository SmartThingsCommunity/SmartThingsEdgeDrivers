-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local utils = require "st.utils"
local configurations = require "configurations"

local CHILD_ENDPOINT = 2

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE and
    not (device.child_ids and utils.table_size(device.child_ids) ~= 0) and
    find_child(device, CHILD_ENDPOINT) == nil then

    local name = "AURORA Outlet 2"
    local metadata = {
      type = "EDGE_CHILD",
      label = name,
      profile = "switch-power-smartplug",
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%02X", CHILD_ENDPOINT),
      vendor_provided_label = name,
    }
    driver:try_create_device(metadata)
  end
  do_refresh(driver, device)
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local zigbee_dual_metering_switch = {
  NAME = "zigbee dual metering switch",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    added = device_added
  },
  can_handle = require("zigbee-dual-metering-switch.can_handle"),
}

return zigbee_dual_metering_switch
