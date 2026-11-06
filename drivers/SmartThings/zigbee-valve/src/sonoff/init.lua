-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local Identify = zcl_clusters.Identify
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local st_device = require "st.device"

local CONFIGURATION = {
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
    minimum_interval = 30,
    maximum_interval = 21600,
    data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
    reportable_change = 1
  },
  {
    cluster = OnOff.ID,
    attribute = OnOff.attributes.OnOff.ID,
    minimum_interval = 0,
    maximum_interval = 600,
    data_type = OnOff.attributes.OnOff.base_type
  }
}

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function is_dual_channel(device)
  local model = device:get_model()
  return model == "SWV-ZF2U" or model == "SWV-ZF2"
end

--- Map OnOff reports to the corresponding valve.
local function onoff_attr_handler(driver, device, value, zb_rx)
  local ep = zb_rx.address_header.src_endpoint.value
  local target = device
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE and is_dual_channel(device) and ep == 0x02 then
    target = find_child(device, 2)
    if not target then return end
  end
  if value.value ~= false and value.value ~= 0 then
    target:emit_event(capabilities.valve.valve.open())
  else
    target:emit_event(capabilities.valve.valve.closed())
  end
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    if is_dual_channel(device) then
      device:set_find_child(find_child)
    end
    for _, attribute in ipairs(CONFIGURATION) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function do_configure(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:refresh()
    device:configure()
  end
end

local function device_added(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE and is_dual_channel(device) then
    if find_child(device, 2) == nil then
      driver:try_create_device({
        type = "EDGE_CHILD",
        label = string.format("%s 2", device.label),
        profile = "valve",
        parent_device_id = device.id,
        parent_assigned_child_key = string.format("%02X", 2),
        vendor_provided_label = string.format("%s 2", device.label),
      })
    end
  end
  device:refresh()
end

local function driver_switched(driver, device)
  device_added(driver, device)
end

--- A device button press prompts a refresh of both SWV2C channels.
local function identify_handler(driver, device, zb_rx)
  if not is_dual_channel(device) then return end
  device.thread:call_with_delay(2, function()
    device:send(OnOff.attributes.OnOff:read(device))
    device:send(OnOff.attributes.OnOff:read(device):to_endpoint(0x02))
  end)
end

local sonoff_valve_handler = {
  NAME = "SONOFF Water Valve Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    driverSwitched = driver_switched,
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = onoff_attr_handler
      }
    },
    cluster = {
      [Identify.ID] = {
        [Identify.server.commands.Identify.ID] = identify_handler
      }
    }
  },
  can_handle = require "sonoff.can_handle",
}

return sonoff_valve_handler
