-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities      = require "st.capabilities"
local clusters          = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local consts              = require "lock_utils.constants"
local lock_utils          = require "lock_utils.utils"
local tables              = require "lock_utils.tables"
local capability_handlers = require "lock_handlers.capabilities"
local zigbee_handlers     = require "lock_handlers.zigbee_responses"

local Alarms             = clusters.Alarms
local DoorLock           = clusters.DoorLock
local PowerConfiguration = clusters.PowerConfiguration
local DoorState          = DoorLock.attributes.DoorState

local PIN_USERS_SUPPORTED = 1
local SYNC_DELAY = 15

local function sync_after_delay(device)
  device.thread:call_with_delay(SYNC_DELAY, function() lock_utils.sync_device_state(device) end)
end

local function refresh_and_sync(driver, device)
  driver:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })
  sync_after_delay(device)
end

local function emit_pin_users_supported(device)
  device:emit_event(capabilities.lockCredentials.pinUsersSupported(PIN_USERS_SUPPORTED, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockUsers.totalUsersSupported(PIN_USERS_SUPPORTED, { visibility = { displayed = false } }))
end

-- The profile of the DLM-300Z does not have the deprecated lockCodes, which the default handler
-- requires to migrate a newly joined device to lockUsers/lockCredentials. It is migrated here.
local function device_added(driver, device)
  device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
  driver.lifecycle_handlers.added(driver, device)
end

local function device_init(driver, device)
  -- A newly joined device is migrated when it is added. A device that joined before this sub-driver
  -- existed is migrated here, as the DLM-300Z is always handled with lockUsers/lockCredentials.
  local needs_sync = not device:get_field(consts.DRIVER_STATE.SLGA_MIGRATED)
  if needs_sync then
    device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
  end
  driver.lifecycle_handlers.init(driver, device)
  -- The DLM-300Z has no latch, and does not report the "not fully locked" or "unknown" state
  device:emit_event(capabilities.lock.supportedLockValues({ "locked", "unlocked" }, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lock.supportedLockCommands({ "lock", "unlock" }, { visibility = { displayed = false } }))
  if device:supports_capability(capabilities.lockCredentials) then
    -- The default handler only reports the PIN support of a device that has lockCodes in its profile
    device:emit_event(capabilities.lockCredentials.supportedCredentials({ consts.CRED_TYPE_PIN }, { visibility = { displayed = false } }))
    emit_pin_users_supported(device)
  end
  if needs_sync then refresh_and_sync(driver, device) end
end

local function do_configure(driver, device)
  local hub_eui = driver.environment_info.hub_zigbee_eui

  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, hub_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 600, 21600, 1))

  device:send(device_management.build_bind_request(device, DoorLock.ID, hub_eui))
  device:send(DoorLock.attributes.LockState:configure_reporting(device, 0, 3600, 0))
  device:send(DoorState:configure_reporting(device, 0, 3600))

  device:send(device_management.build_bind_request(device, Alarms.ID, hub_eui))
  -- The DLM-300Z reports when the change is greater than or equal to the reportable change, not
  -- only when it exceeds it. With a reportable change of 0 it therefore reports the AlarmCount
  -- every second, so the reportable change is set to 1.
  device:send(Alarms.attributes.AlarmCount:configure_reporting(device, 0, 21600, 1))

  device:emit_event(capabilities.battery.type("AA"))
  device:emit_event(capabilities.battery.quantity(4))

  sync_after_delay(device)
end

local function refresh(driver, device, command)
  capability_handlers.refresh(driver, device, command)
  device:send(DoorState:read(device))
end

local function finish_delete_all(device, succeeded)
  local status = succeeded and consts.COMMAND_RESULT.SUCCESS or consts.COMMAND_RESULT.FAILURE
  local users_too = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS) == consts.LOCK_USERS.DELETE_ALL
  if succeeded then
    if users_too then
      tables.delete_all_entries(device, "users")
    else
      -- The user of a deleted PIN is deleted with it, as it is when a single credential is deleted.
      -- Otherwise the only user slot of the DLM-300Z stays taken by a user that has no PIN.
      for _, credential in ipairs(tables.get_state(device, "credentials") or {}) do
        tables.delete_entry(device, "users", credential.userIndex)
      end
    end
    tables.delete_all_entries(device, "credentials")
  end
  if users_too then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE_ALL, status)
  end
  lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE_ALL, status)
  lock_utils.clear_busy_state(device)
end

-- The DLM-300Z does not support ClearAllPINCodes, so its single PIN is cleared instead.
local function delete_all_credentials(driver, device, command)
  if device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS) ~= consts.LOCK_USERS.DELETE_ALL then
    if lock_utils.is_device_busy(device) then
      lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE_ALL, consts.COMMAND_RESULT.BUSY)
      return
    end
    lock_utils.set_busy_state(device, consts.LOCK_CREDENTIALS.DELETE_ALL, command.args)
  end

  local credential = (tables.get_state(device, "credentials") or {})[1]
  if credential then
    device:send(DoorLock.attributes.SendPINOverTheAir:write(device, true))
    device:send(DoorLock.server.commands.ClearPINCode(device, credential.credentialIndex))
  else
    finish_delete_all(device, true) -- there is no PIN to clear
  end
end

-- The response to the ClearPINCode that was sent to delete all the credentials
local function clear_pin_code_response(driver, device, zb_rx)
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  if command_in_progress == consts.LOCK_USERS.DELETE_ALL or command_in_progress == consts.LOCK_CREDENTIALS.DELETE_ALL then
    finish_delete_all(device, zb_rx.body.zcl_body.status.value == DoorLock.types.DrlkPassFailStatus.PASS)
  else
    zigbee_handlers.clear_pin_code_response(driver, device, zb_rx)
  end
end

-- The default handler switches a device without lockCodes to the base-lock profile
local function number_of_pin_users_supported_handler(driver, device, value)
  emit_pin_users_supported(device)
end

local function door_state_handler(driver, device, value)
  if value.value == DoorState.OPEN then
    device:emit_event(capabilities.contactSensor.contact.open())
  elseif value.value == DoorState.CLOSED then
    device:emit_event(capabilities.contactSensor.contact.closed())
  end
end

local shinasystems_lock_driver = {
  NAME = "ShinaSystem Lock",
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    doConfigure = do_configure,
  },
  capability_handlers = {
    [capabilities.lockCredentials.ID] = {
      [capabilities.lockCredentials.commands.deleteAllCredentials.NAME] = delete_all_credentials,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh,
    },
  },
  zigbee_handlers = {
    cluster = {
      [DoorLock.ID] = {
        [DoorLock.client.commands.ClearPINCodeResponse.ID] = clear_pin_code_response,
      }
    },
    attr = {
      [DoorLock.ID] = {
        [DoorState.ID] = door_state_handler,
        [DoorLock.attributes.NumberOfPINUsersSupported.ID] = number_of_pin_users_supported_handler,
      }
    }
  },
  can_handle = require("shinasystems.can_handle"),
}

return shinasystems_lock_driver
