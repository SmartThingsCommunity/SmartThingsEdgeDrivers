-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local log = require "log"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic = zcl_clusters.Basic
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local st_device = require "st.device"
local utils = require "st.utils"

local BATTERY_POLL_INTERVAL = 7200

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

--- OnOff Property Reporting → Valve Capability Point Event
local function onoff_attr_handler(driver, device, value, zb_rx)
  local ep = zb_rx.address_header.src_endpoint.value
  local target = device
  if ep == 0x02 then
    local child = find_child(device, 2)
    if child then target = child end
  end
  log.info(string.format("[SWV] OnOff report ep=%s value=%s", tostring(ep), tostring(value.value)))
  if value.value == true or value.value == 1 then
    target:emit_event(capabilities.valve.valve.open())
  else
    target:emit_event(capabilities.valve.valve.closed())
  end
end

--- Battery Percentage Attribute Handler
local function battery_percentage_handler(driver, device, value)
  device:emit_event(capabilities.battery.battery(utils.round(value.value / 2)))
end

--- Lifecycle initialization handler
local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
    device.thread:call_on_schedule(
      BATTERY_POLL_INTERVAL,
      function()
        device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
      end
    )
  end
end

--- doConfigure
local function do_configure(driver, device)
  device:try_update_metadata({ provisioning_state = "PROVISIONED" })
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:emit_event(capabilities.valve.valve.closed())
    device:emit_event(capabilities.battery.battery(100))
  else
    device:emit_event(capabilities.valve.valve.closed())
  end
end

--- added
local function device_added(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
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
  else
    device:emit_event(capabilities.valve.valve.closed())
  end
end

--- driverSwitched
local function driver_switched(driver, device)
  device_added(driver, device)
end

--- valve.open
local function valve_open_handler(driver, device, command)
  device:send(OnOff.server.commands.On(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

--- valve.close
local function valve_close_handler(driver, device, command)
  device:send(OnOff.server.commands.Off(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

--- Identity cluster handler：button pressed on the device, sync valve states
local function identify_handler(driver, device, zb_rx)
  log.info("[SWV] Identify received, syncing valve states")
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
  capability_handlers = {
    [capabilities.valve.ID] = {
      [capabilities.valve.commands.open.NAME] = valve_open_handler,
      [capabilities.valve.commands.close.NAME] = valve_close_handler,
    }
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = onoff_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percentage_handler
      }
    },
    cluster = {
      [Basic.ID] = {
        [Basic.server.commands.ResetToFactoryDefaults.ID] = identify_handler
      }
    }
  },
  can_handle = require "sonoff.can_handle",
}

return sonoff_valve_handler
