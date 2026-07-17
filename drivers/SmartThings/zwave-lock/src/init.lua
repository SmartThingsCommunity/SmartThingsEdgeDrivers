-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})

local capabilities = require "st.capabilities"

local consts              = require "lock_utils.constants"
local table_utils         = require "lock_utils.tables"
local zwave_handlers      = require "lock_handlers.zwave_responses"
local capability_handlers = require "lock_handlers.capabilities"


local LockLifecycle = {}

function LockLifecycle.device_added(driver, device)
  if device:supports_capability(capabilities.tamperAlert) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
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
  end

  if device:supports_capability(capabilities.tamperAlert) then
    -- ensure our user/credential state is accurate to the current device state
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

function LockLifecycle.driver_switched(driver, device)
  if device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.migrated.NAME) == true then
    device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
  end
  device:try_update_metadata({ provisioning_state = "PROVISIONED" })
end

local driver_template = {
  lifecycle_handlers = {
    added = LockLifecycle.device_added,
    driver_switched = LockLifecycle.driver_switched,
    init = LockLifecycle.init,
  },
  zwave_handlers = {
    [cc.TIME] = {
      [0x01] = zwave_handlers.time_get_handler -- used by DanaLock
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = zwave_handlers.notification_report
    },
    [cc.USER_CODE] = {
      [UserCode.REPORT] = zwave_handlers.user_code_report,
      [UserCode.USERS_NUMBER_REPORT] = zwave_handlers.users_number_report,
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
    capabilities.lockCodes,
    capabilities.lockUsers,
    capabilities.lockCredentials,
    capabilities.battery,
    capabilities.tamperAlert,
  },
  sub_drivers = require("sub_drivers"),
  shared_device_thread_enabled = true,
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local lock = ZwaveDriver("zwave_lock", driver_template)
lock:run()
