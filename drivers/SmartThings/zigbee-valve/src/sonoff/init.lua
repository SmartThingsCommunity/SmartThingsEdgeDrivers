--[[
Description: SONOFF Water Valve sub-driver for zigbee-valve
             Parent (ep1) + EDGE_CHILD (ep2), shared battery
Version: 4.1
Author: guoxin.yang
Date: 2026-07-12
--]]
local capabilities = require "st.capabilities"
local log = require "log"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local st_device = require "st.device"
local utils = require "st.utils"

local BATTERY_POLL_INTERVAL = 7200

local FINGERPRINTS = {
  { mfr = "SONOFF", model = "SWV-ZF2U" }
}

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

--- OnOff 属性上报 → valve 事件（按 src_endpoint 路由）
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

--- 电池百分比
local function battery_percentage_handler(driver, device, value)
  device:emit_event(capabilities.battery.battery(utils.round(value.value / 2)))
end

--- 生命周期 init（仅父设备）
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

--- Identity cluster handler：物理按键 → 2秒后读两个端点状态
local function identify_handler(driver, device, zb_rx)
  log.info("[SWV] Identify received, syncing valve states")
  device.thread:call_with_delay(2, function()
    device:send(OnOff.attributes.OnOff:read(device))
    device:send(OnOff.attributes.OnOff:read(device):to_endpoint(0x02))
  end)
end

--- 设备匹配
local function is_sonoff_valve(opts, driver, device)
  for _, fp in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fp.mfr and device:get_model() == fp.model then
      return true
    end
  end
  return device.parent_device_id ~= nil
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
    }
  },
  can_handle = is_sonoff_valve
}

return sonoff_valve_handler
