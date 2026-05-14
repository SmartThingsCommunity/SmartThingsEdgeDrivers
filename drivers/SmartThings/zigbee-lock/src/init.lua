-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZigbeeDriver      = require "st.zigbee"
local defaults          = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"
local clusters          = require "st.zigbee.zcl.clusters"
local capabilities      = require "st.capabilities"

local consts              = require "lock_utils.constants"
local lock_utils          = require "lock_utils.utils"
local table_utils         = require "lock_utils.tables"
local zigbee_handlers     = require "lock_handlers.zigbee_responses"
local capability_handlers = require "lock_handlers.capabilities"

local LockLifecycle = {}

function LockLifecycle.device_added(driver, device)
  if device:supports_capability(capabilities.lockCodes) and device._provisioning_state == "TYPED" then
    -- set the migrated field to true so new devices use lockCredentials/lockUsers from the start.
    -- auto-migration is only run for typed devices, as provisioned devices have already been onboarded,
    -- and should be migrated manually by the user.
    device:emit_event(capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true }) -- persist the migration event in the datastore
  end
  -- set initial state
  driver:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })
end

function LockLifecycle.init(driver, device)
  -- Restore users/credentials capability state from the persistent store in case
  -- the capability state cache was wiped since the last driver run.
  table_utils.restore_from_persistent_store(device)

  local lock_pins_supported_by_profile = device:supports_capability(capabilities.lockCodes)
  if lock_pins_supported_by_profile and device:get_field(consts.DRIVER_STATE.SLGA_MIGRATED) == true then
    -- ensure lockCodes capability state is reflected correctly for already migrated devices
    device:emit_event(capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    device:emit_event(capabilities.lockCredentials.supportedCredentials({ consts.CRED_TYPE_PIN }, { visibility = { displayed = false } }))
  elseif not lock_pins_supported_by_profile then
    -- generically fingerprinted profiles do not have any codes/users/credentials capabilities.
    -- We should check its PIN users if it should be re-profiled.
    device:send(clusters.DoorLock.attributes.NumberOfPINUsersSupported:read(device))
  end
end

function LockLifecycle.do_configure(driver, device)
  device:send(device_management.build_bind_request(device, clusters.PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui))
  device:send(clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 600, 21600, 1))

  device:send(device_management.build_bind_request(device, clusters.DoorLock.ID, driver.environment_info.hub_zigbee_eui))
  device:send(clusters.DoorLock.attributes.LockState:configure_reporting(device, 0, 3600, 0))

  device:send(device_management.build_bind_request(device, clusters.Alarms.ID, driver.environment_info.hub_zigbee_eui))
  device:send(clusters.Alarms.attributes.AlarmCount:configure_reporting(device, 0, 21600, 0))

  if device:supports_capability(capabilities.lockCredentials) then
    -- ensure our user/credential state is accurate to the current device state
    device.thread:call_with_delay(15, function() lock_utils.sync_device_state(device) end)
  end
end

function LockLifecycle.info_changed(driver, device, event, args)
  local profile_switched = device.profile.id ~= args.old_st_store.profile.id
  if profile_switched and device:supports_capability(capabilities.lockCodes) then
    -- ensure all slga migration steps are run, and that the latest device state is synced to the driver.
    device:emit_event(capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
    if device:supports_capability(capabilities.lockCredentials) then
      device:emit_event(capabilities.lockCredentials.supportedCredentials({ consts.CRED_TYPE_PIN }, { visibility = { displayed = false } }))
    end
    -- ensure all requisite initial state is set
    driver:inject_capability_command(device, {
      capability = capabilities.refresh.ID,
      command = capabilities.refresh.commands.refresh.NAME,
      args = {}
    })
    -- ensure our user/credential state is accurate to the current device state
    device.thread:call_with_delay(15, function() lock_utils.sync_device_state(device) end)
  end
end

local zigbee_lock_driver = {
  lifecycle_handlers = {
    added = LockLifecycle.device_added,
    init = LockLifecycle.init,
    doConfigure = LockLifecycle.do_configure,
    infoChanged = LockLifecycle.info_changed,
  },
  zigbee_handlers = {
    cluster = {
      [clusters.Alarms.ID] = {
        [clusters.Alarms.client.commands.Alarm.ID] = zigbee_handlers.alarm
      },
      [clusters.DoorLock.ID] = {
        [clusters.DoorLock.client.commands.ClearAllPINCodesResponse.ID] = zigbee_handlers.clear_all_pin_codes_response,
        [clusters.DoorLock.client.commands.ClearPINCodeResponse.ID] = zigbee_handlers.clear_pin_code_response,
        [clusters.DoorLock.client.commands.GetPINCodeResponse.ID] = zigbee_handlers.get_pin_code_response,
        [clusters.DoorLock.client.commands.ProgrammingEventNotification.ID] = zigbee_handlers.programming_event_notification,
        [clusters.DoorLock.client.commands.OperatingEventNotification.ID] = zigbee_handlers.operating_event_notification,
        [clusters.DoorLock.client.commands.SetPINCodeResponse.ID] = zigbee_handlers.set_pin_code_response,
      }
    },
    attr = {
      [clusters.DoorLock.ID] = {
        [clusters.DoorLock.attributes.LockState.ID] = zigbee_handlers.lock_state,
        [clusters.DoorLock.attributes.MaxPINCodeLength.ID] = zigbee_handlers.max_pin_code_length,
        [clusters.DoorLock.attributes.MinPINCodeLength.ID] = zigbee_handlers.min_pin_code_length,
        [clusters.DoorLock.attributes.NumberOfPINUsersSupported.ID] = zigbee_handlers.number_of_pin_users_supported,
      }
    }
  },
  capability_handlers = {
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = capability_handlers.lock,
      [capabilities.lock.commands.unlock.NAME] = capability_handlers.unlock,
    },
    [capabilities.lockUsers.ID] = {
      [capabilities.lockUsers.commands.addUser.NAME] = capability_handlers.add_user,
      [capabilities.lockUsers.commands.updateUser.NAME] = capability_handlers.update_user,
      [capabilities.lockUsers.commands.deleteUser.NAME] = capability_handlers.delete_user,
      [capabilities.lockUsers.commands.deleteAllUsers.NAME] = capability_handlers.delete_all_users,
    },
    [capabilities.lockCredentials.ID] = {
      [capabilities.lockCredentials.commands.addCredential.NAME] = capability_handlers.add_credential,
      [capabilities.lockCredentials.commands.updateCredential.NAME] = capability_handlers.update_credential,
      [capabilities.lockCredentials.commands.deleteCredential.NAME] = capability_handlers.delete_credential,
      [capabilities.lockCredentials.commands.deleteAllCredentials.NAME] = capability_handlers.delete_all_credentials,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = capability_handlers.refresh,
    },
  },
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCredentials,
    capabilities.lockUsers,
    capabilities.battery,
  },
  sub_drivers = require("sub_drivers"),
  health_check = false,
  shared_device_thread_enabled = true,
}

defaults.register_for_default_handlers(zigbee_lock_driver, zigbee_lock_driver.supported_capabilities)
local driver = ZigbeeDriver("zigbee-lock", zigbee_lock_driver)
driver:run()
