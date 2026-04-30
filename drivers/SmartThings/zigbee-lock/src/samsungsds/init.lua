-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock
local Lock = capabilities.lock
local consts = require "lock_utils.constants"
local tables = require "lock_utils.tables"
local socket = require "cosock.socket"

local SAMSUNG_SDS_MFR_SPECIFIC_UNLOCK_COMMAND = 0x1F
local SAMSUNG_SDS_MFR_CODE = 0x0003

local function handle_lock_state(driver, device, value, zb_rx)
  if value.value == DoorLock.attributes.LockState.LOCKED then
    device:emit_event(Lock.lock.locked())
  elseif value.value == DoorLock.attributes.LockState.UNLOCKED then
    device:emit_event(Lock.lock.unlocked())
  end
end

local function mfg_lock_door_handler(driver, device, zb_rx)
  local cmd = zb_rx.body.zcl_body.body_bytes:byte(1)
  if cmd == 0x00 then
    device:emit_event(Lock.lock.unlocked())
  end
end

local function unlock_cmd_handler(driver, device, command)
  device:send(cluster_base.build_manufacturer_specific_command(
          device,
          DoorLock.ID,
          SAMSUNG_SDS_MFR_SPECIFIC_UNLOCK_COMMAND,
          SAMSUNG_SDS_MFR_CODE,
          "\x10\x04\x31\x32\x33\x35"))
end

local function lock_cmd_handler(driver, device, command)
  -- do nothing in lock command handler
end

local refresh = function(driver, device, cmd)
  -- do nothing in refresh capability handler
end

local function emit_event_if_latest_state_missing(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

local device_added = function(self, device)
  device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true }) -- set migrated for all Samsung SDS devices. They do not require any legacy functionality.

  emit_event_if_latest_state_missing(device, "main", capabilities.lock, capabilities.lock.lock.NAME, capabilities.lock.lock.unlocked())
  device:emit_event(capabilities.battery.battery(100))
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, DoorLock.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(DoorLock.attributes.LockState:configure_reporting(device, 0, 3600, 0))
end

local battery_init = battery_defaults.build_linear_voltage_init(4.0, 6.0)

local device_init = function(driver, device, event)
  device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true }) -- set migrated for all Samsung SDS devices. They do not require any legacy functionality.
  battery_init(driver, device, event)
  device:remove_monitored_attribute(clusters.PowerConfiguration.ID, clusters.PowerConfiguration.attributes.BatteryVoltage.ID)
  device:remove_configured_attribute(clusters.PowerConfiguration.ID, clusters.PowerConfiguration.attributes.BatteryVoltage.ID)
end

local operating_event_notification = function(driver, device, zb_rx)
  local op_event_code = tonumber(zb_rx.body.zcl_body.operation_event_code.value)
  local op_event_source = tonumber(zb_rx.body.zcl_body.operation_event_source.value)

  -- get lock event or return
  local OpEventCode = clusters.DoorLock.types.OperationEventCode
  local OP_EVENT_CODE_CAPABILITY_MAP = {
    [OpEventCode.LOCK]            = capabilities.lock.lock.locked(),
    [OpEventCode.UNLOCK]          = capabilities.lock.lock.unlocked(),
    [OpEventCode.ONE_TOUCH_LOCK]  = capabilities.lock.lock.locked(),
    [OpEventCode.KEY_LOCK]        = capabilities.lock.lock.locked(),
    [OpEventCode.KEY_UNLOCK]      = capabilities.lock.lock.unlocked(),
    [OpEventCode.AUTO_LOCK]       = capabilities.lock.lock.locked(),
    [OpEventCode.MANUAL_LOCK]     = capabilities.lock.lock.locked(),
    [OpEventCode.MANUAL_UNLOCK]   = capabilities.lock.lock.unlocked(),
    [OpEventCode.SCHEDULE_LOCK]   = capabilities.lock.lock.locked(),
    [OpEventCode.SCHEDULE_UNLOCK] = capabilities.lock.lock.unlocked()
  }
  local lock_event = OP_EVENT_CODE_CAPABILITY_MAP[op_event_code]
  if not lock_event then return end
  lock_event.data = {}

  -- get method of lock event
  local OpEventSource = clusters.DoorLock.types.DrlkOperationEventSource
  local OP_EVENT_SOURCE_CAPABILITY_MAP = {
    [OpEventSource.KEYPAD] = "keypad",
    [OpEventSource.RF]     = "command",
    [OpEventSource.MANUAL] = "manual",
    [OpEventSource.RFID]   = "rfid",
    -- These last two sources are not found in the spec, but they were in
    -- the legacy driver and appear to be related to the Samsung SDS
    [4] = "fingerprint",
    [5] = "bluetooth",
  }
  if (op_event_source ~= OpEventSource.KEYPAD and (
    op_event_code == OpEventCode.AUTO_LOCK or
    op_event_code == OpEventCode.SCHEDULE_LOCK or
    op_event_code == OpEventCode.SCHEDULE_UNLOCK
  )) then
    lock_event.data.method = "auto"
  else
    lock_event.data.method = OP_EVENT_SOURCE_CAPABILITY_MAP[op_event_source] or "manual"
  end

  -- get stored lockUsers data if applicable
  if op_event_source == OpEventSource.KEYPAD and device:supports_capability(capabilities.lockUsers) then
    local user_id = tonumber(zb_rx.body.zcl_body.user_id.value)
    local associated_user = tables.find_entry(device, "users", user_id)
    if associated_user then
      lock_event.data.userIndex = user_id .. ""
      lock_event.data.userName = associated_user.userName
      lock_event.data.userType = associated_user.userType
    else
      lock_event.data.userIndex = user_id .. ""
      lock_event.data.userName = "User " .. user_id -- default
    end
  end

  -- if this is an event corresponding to a recently-received attribute report, we
  -- want to set our delay timer for future lock attribute report events
  local endpoint_id = zb_rx.address_header.src_endpoint.value
  if lock_event.value.value == device:get_latest_state(
    device:get_component_id_for_endpoint(endpoint_id),
    capabilities.lock.ID,
    capabilities.lock.lock.ID
  ) then
    local preceding_event_time = device:get_field(consts.DELAY_LOCK_EVENT) or 0
    local time_diff = socket.gettime() - preceding_event_time
    if time_diff < consts.MAX_DELAY then
      device:set_field(consts.DELAY_LOCK_EVENT, time_diff)
    end
  end

  device:emit_event_for_endpoint(endpoint_id, lock_event)
end

local samsung_sds_driver = {
  NAME = "SAMSUNG SDS Lock Driver",
  zigbee_handlers = {
    cluster = {
      [DoorLock.ID] = {
        [SAMSUNG_SDS_MFR_SPECIFIC_UNLOCK_COMMAND] = mfg_lock_door_handler,
        [clusters.DoorLock.client.commands.OperatingEventNotification.ID] = operating_event_notification,
      }
    },
    attr = {
      [DoorLock.ID] = {
        [DoorLock.attributes.LockState.ID] = handle_lock_state
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    },
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.unlock.NAME] = unlock_cmd_handler,
      [capabilities.lock.commands.lock.NAME] = lock_cmd_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = device_added,
    init = device_init
  },
  can_handle = require("samsungsds.can_handle"),
}

return samsung_sds_driver
